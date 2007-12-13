# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Bugzilla Bug Tracking System.
#
# The Initial Developer of the Original Code is Oracle Corporation.
# Portions created by Oracle are Copyright (C) 2007 Oracle Corporation.
# All Rights Reserved.
#
# Contributor(s): Lance Larsh <lance.larsh@oracle.com>
#                 Xiaoou Wu <xiaoou.wu@oracle.com>
#                 Max Kanat-Alexander <mkanat@bugzilla.org>

package Bugzilla::DB::Schema::Oracle;

###############################################################################
#
# DB::Schema implementation for Oracle
#
###############################################################################

use strict;

use base qw(Bugzilla::DB::Schema);
use Carp qw(confess);
use Digest::MD5  qw(md5_hex);
use Bugzilla::Util;

use constant ADD_COLUMN      => 'ADD';

#------------------------------------------------------------------------------
sub _initialize {

    my $self = shift;

    $self = $self->SUPER::_initialize(@_);

    $self->{db_specific} = {

        BOOLEAN =>      'integer',
        FALSE =>        '0', 
        TRUE =>         '1',

        INT1 =>         'integer',
        INT2 =>         'integer',
        INT3 =>         'integer',
        INT4 =>         'integer',

        SMALLSERIAL  => 'integer',
        MEDIUMSERIAL => 'integer',
        INTSERIAL    => 'integer',

        TINYTEXT   =>   'varchar(255)',
        MEDIUMTEXT =>   'varchar(4000)',
        LONGTEXT   =>   'clob',

        LONGBLOB =>     'blob',

        DATETIME =>     'date',

    };

    $self->_adjust_schema;

    return $self;

} #eosub--_initialize
#--------------------------------------------------------------------

sub get_table_ddl {
    my $self = shift;
    my $table = shift;
    unshift @_, $table;
    my @ddl = $self->SUPER::get_table_ddl(@_);

    my @fields = @{ $self->{abstract_schema}{$table}{FIELDS} || [] };
    while (@fields) {
        my $field_name = shift @fields;
        my $field_info = shift @fields;
        # Create triggers to deal with empty string. 
        if ( $field_info->{TYPE} =~ /varchar|TEXT/i 
                && $field_info->{NOTNULL} ) {
             push (@ddl, _get_notnull_trigger_ddl($table, $field_name));
        }
        # Create sequences and triggers to emulate SERIAL datatypes.
        if ( $field_info->{TYPE} =~ /SERIAL/i ) {
            push (@ddl, $self->_get_create_seq_ddl($table, $field_name));
        }
    }
    return @ddl;

} #eosub--get_table_ddl

# Extend superclass method to create Oracle Text indexes if index type 
# is FULLTEXT from schema. Returns a "create index" SQL statement.
sub _get_create_index_ddl {

    my ($self, $table_name, $index_name, $index_fields, $index_type) = @_;
    $index_name = "idx_" . substr(md5_hex($index_name),0,20);
    if ($index_type eq 'FULLTEXT') {
        my $sql = "CREATE INDEX $index_name ON $table_name (" 
                  . join(',',@$index_fields)
                  . ") INDEXTYPE IS CTXSYS.CONTEXT "
                  . " PARAMETERS('LEXER BZ_LEX SYNC(ON COMMIT)')" ;
        return $sql;
    }

    return($self->SUPER::_get_create_index_ddl($table_name, $index_name, 
                                               $index_fields, $index_type));

} #eosub--_get_create_index_ddl

# Oracle supports the use of FOREIGN KEY integrity constraints 
# to define the referential integrity actions, including:
# - Update and delete No Action (default)
# - Delete CASCADE
# - Delete SET NULL
sub get_fk_ddl {
    my ($self, $table, $column, $references) = @_;
    return "" if !$references;

    my $update    = $references->{UPDATE} || 'CASCADE';
    my $delete    = $references->{DELETE};
    my $to_table  = $references->{TABLE}  || confess "No table in reference";
    my $to_column = $references->{COLUMN} || confess "No column in reference";
    my $fk_name   = $self->_get_fk_name($table, $column, $references);

    my $fk_string = "\n     CONSTRAINT $fk_name FOREIGN KEY ($column)\n"
                    . "     REFERENCES $to_table($to_column)\n";
   
    $fk_string    = $fk_string . "     ON DELETE $delete" if $delete; 
    
    if ( $update =~ /CASCADE/i ){
        my $tr_str = "CREATE OR REPLACE TRIGGER ${fk_name}_UC"
                     . " AFTER  UPDATE  ON ". $table
                     . " REFERENCING "
                     . " NEW AS NEW "
                     . " OLD AS OLD "
                     . " FOR EACH ROW "
                     . " BEGIN "
                     . "     UPDATE $to_table"
                     . "        SET $to_column = :NEW.$column"
                     . "      WHERE $to_column = :OLD.$column;"
                     . " END ${fk_name}_UC;";
        my $dbh = Bugzilla->dbh; 
        $dbh->do($tr_str);      
    }

    return $fk_string;
}

sub get_drop_fk_sql {
    my $self = shift;
    my ($table, $column, $references) = @_;
    my $fk_name = $self->_get_fk_name(@_);
    my @sql;
    if (!$references->{UPDATE} || $references->{UPDATE} =~ /CASCADE/i) {
        push(@sql, "DROP TRIGGER ${fk_name}_uc");
    }
    push(@sql, $self->SUPER::get_drop_fk_sql(@_));
    return @sql;
}

sub _get_fk_name {
    my ($self, $table, $column, $references) = @_;
    my $to_table  = $references->{TABLE};
    my $to_column = $references->{COLUMN};
    my $fk_name   = "${table}_${column}_${to_table}_${to_column}";
    $fk_name      = "fk_" . substr(md5_hex($fk_name),0,20);
    
    return $fk_name;
}

sub _get_notnull_trigger_ddl {
      my ($table, $column) = @_;

      my $notnull_sql = "CREATE OR REPLACE TRIGGER "
                        . " ${table}_${column}"
                        . " BEFORE INSERT OR UPDATE ON ". $table
                        . " FOR EACH ROW"
                        . " BEGIN "
                        . " IF :NEW.". $column ." IS NULL THEN  "
                        . " SELECT '" . Bugzilla::DB::Oracle->EMPTY_STRING
                        . "' INTO :NEW.". $column ." FROM DUAL; "
                        . " END IF; "
                        . " END ".$table.";";
     return $notnull_sql;
}

sub _get_create_seq_ddl {
     my ($self, $table, $column, $start_with) = @_;
     $start_with ||= 1;
     my @ddl;
     my $seq_name = "${table}_${column}_SEQ";
     my $seq_sql = "CREATE SEQUENCE $seq_name "
                   . " INCREMENT BY 1 "
                   . " START WITH $start_with "
                   . " NOMAXVALUE "
                   . " NOCYCLE "
                   . " NOCACHE";
     my $serial_sql = "CREATE OR REPLACE TRIGGER ${table}_${column}_TR "
                    . " BEFORE INSERT ON ${table} "
                    . " FOR EACH ROW "
                    . " BEGIN "
                    . "   SELECT ${seq_name}.NEXTVAL "
                    . "   INTO :NEW.${column} FROM DUAL; "
                    . " END;";
    push (@ddl, $seq_sql);
    push (@ddl, $serial_sql);

    return @ddl;
}

1;

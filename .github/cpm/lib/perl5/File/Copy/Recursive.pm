package File::Copy::Recursive;

use strict;

BEGIN {
    # Keep older versions of Perl from trying to use lexical warnings
    $INC{'warnings.pm'} = "fake warnings entry for < 5.6 perl ($])" if $] < 5.006;
}
use warnings;

use Carp;
use File::Copy;
use File::Spec;    #not really needed because File::Copy already gets it, but for good measure :)
use Cwd ();

use vars qw(
  @ISA      @EXPORT_OK $VERSION  $MaxDepth $KeepMode $CPRFComp $CopyLink
  $PFSCheck $RemvBase $NoFtlPth  $ForcePth $CopyLoop $RMTrgFil $RMTrgDir
  $CondCopy $BdTrgWrn $SkipFlop  $DirPerms
);

require Exporter;
@ISA       = qw(Exporter);
@EXPORT_OK = qw(fcopy rcopy dircopy fmove rmove dirmove pathmk pathrm pathempty pathrmdir rcopy_glob rmove_glob);

$VERSION = '0.45';

$MaxDepth = 0;
$KeepMode = 1;
$CPRFComp = 0;
$CopyLink = eval { local $SIG{'__DIE__'}; symlink '', ''; 1 } || 0;
$PFSCheck = 1;
$RemvBase = 0;
$NoFtlPth = 0;
$ForcePth = 0;
$CopyLoop = 0;
$RMTrgFil = 0;
$RMTrgDir = 0;
$CondCopy = {};
$BdTrgWrn = 0;
$SkipFlop = 0;
$DirPerms = 0777;

my $samecheck = sub {
    return 1 if $^O eq 'MSWin32';    # need better way to check for this on winders...
    return if @_ != 2 || !defined $_[0] || !defined $_[1];
    return if $_[0] eq $_[1];

    my $one = '';
    if ($PFSCheck) {
        $one = join( '-', ( stat $_[0] )[ 0, 1 ] ) || '';
        my $two = join( '-', ( stat $_[1] )[ 0, 1 ] ) || '';
        if ( $one eq $two && $one ) {
            carp "$_[0] and $_[1] are identical";
            return;
        }
    }

    if ( -d $_[0] && !$CopyLoop ) {
        $one = join( '-', ( stat $_[0] )[ 0, 1 ] ) if !$one;
        my $abs = File::Spec->rel2abs( $_[1] );
        my @pth = File::Spec->splitdir($abs);
        while (@pth) {
            if ( $pth[-1] eq '..' ) {    # cheaper than Cwd::realpath() plus we don't want to resolve symlinks at this point, right?
                pop @pth;
                pop @pth unless -l File::Spec->catdir(@pth);
                next;
            }
            my $cur = File::Spec->catdir(@pth);
            last if !$cur;               # probably not necessary, but nice to have just in case :)
            my $two = join( '-', ( stat $cur )[ 0, 1 ] ) || '';
            if ( $one eq $two && $one ) {

                # $! = 62; # Too many levels of symbolic links
                carp "Caught Deep Recursion Condition: $_[0] contains $_[1]";
                return;
            }

            pop @pth;
        }
    }

    return 1;
};

my $glob = sub {
    my ( $do, $src_glob, @args ) = @_;

    local $CPRFComp = 1;
    require File::Glob;

    my @rt;
    for my $path ( File::Glob::bsd_glob($src_glob) ) {
        my @call = [ $do->( $path, @args ) ] or return;
        push @rt, \@call;
    }

    return @rt;
};

my $move = sub {
    my $fl = shift;
    my @x;
    if ($fl) {
        @x = fcopy(@_) or return;
    }
    else {
        @x = dircopy(@_) or return;
    }
    if (@x) {
        if ($fl) {
            unlink $_[0] or return;
        }
        else {
            pathrmdir( $_[0] ) or return;
        }
        if ($RemvBase) {
            my ( $volm, $path ) = File::Spec->splitpath( $_[0] );
            pathrm( File::Spec->catpath( $volm, $path, '' ), $ForcePth, $NoFtlPth ) or return;
        }
    }
    return wantarray ? @x : $x[0];
};

my $ok_todo_asper_condcopy = sub {
    my $org  = shift;
    my $copy = 1;
    if ( exists $CondCopy->{$org} ) {
        if ( $CondCopy->{$org}{'md5'} ) {

        }
        if ($copy) {

        }
    }
    return $copy;
};

sub fcopy {
    $samecheck->(@_) or return;
    if ( $RMTrgFil && ( -d $_[1] || -e $_[1] ) ) {
        my $trg = $_[1];
        if ( -d $trg ) {
            my @trgx = File::Spec->splitpath( $_[0] );
            $trg = File::Spec->catfile( $_[1], $trgx[$#trgx] );
        }
        $samecheck->( $_[0], $trg ) or return;
        if ( -e $trg ) {
            if ( $RMTrgFil == 1 ) {
                unlink $trg or carp "\$RMTrgFil failed: $!";
            }
            else {
                unlink $trg or return;
            }
        }
    }
    my ( $volm, $path ) = File::Spec->splitpath( $_[1] );
    if ( $path && !-d $path ) {
        pathmk( File::Spec->catpath( $volm, $path, '' ), $NoFtlPth );
    }
    if ( -l $_[0] && $CopyLink ) {
        my $target = readlink( shift() );
        ($target) = $target =~ m/(.*)/;    # mass-untaint is OK since we have to allow what the file system does
        carp "Copying a symlink ($_[0]) whose target does not exist"
          if !-e $target && $BdTrgWrn;
        my $new = shift();
        unlink $new if -l $new;
        symlink( $target, $new ) or return;
    }
    elsif ( -d $_[0] && -f $_[1] ) {
        return;
    }
    else {
        return if -d $_[0];                # address File::Copy::copy() bug outlined in https://rt.perl.org/Public/Bug/Display.html?id=132866
        copy(@_) or return;

        my @base_file = File::Spec->splitpath( $_[0] );
        my $mode_trg = -d $_[1] ? File::Spec->catfile( $_[1], $base_file[$#base_file] ) : $_[1];

        chmod scalar( ( stat( $_[0] ) )[2] ), $mode_trg if $KeepMode;
    }
    return wantarray ? ( 1, 0, 0 ) : 1;    # use 0's incase they do math on them and in case rcopy() is called in list context = no uninit val warnings
}

sub rcopy {
    if ( -l $_[0] && $CopyLink ) {
        goto &fcopy;
    }

    goto &dircopy if -d $_[0] || substr( $_[0], ( 1 * -1 ), 1 ) eq '*';
    goto &fcopy;
}

sub rcopy_glob {
    $glob->( \&rcopy, @_ );
}

sub dircopy {
    if ( $RMTrgDir && -d $_[1] ) {
        if ( $RMTrgDir == 1 ) {
            pathrmdir( $_[1] ) or carp "\$RMTrgDir failed: $!";
        }
        else {
            pathrmdir( $_[1] ) or return;
        }
    }
    my $globstar = 0;
    my $_zero    = $_[0];
    my $_one     = $_[1];
    if ( substr( $_zero, ( 1 * -1 ), 1 ) eq '*' ) {
        $globstar = 1;
        $_zero = substr( $_zero, 0, ( length($_zero) - 1 ) );
    }

    $samecheck->( $_zero, $_[1] ) or return;
    if ( !-d $_zero || ( -e $_[1] && !-d $_[1] ) ) {
        $! = 20;
        return;
    }

    if ( !-d $_[1] ) {
        pathmk( $_[1], $NoFtlPth ) or return;
    }
    else {
        if ( $CPRFComp && !$globstar ) {
            my @parts = File::Spec->splitdir($_zero);
            while ( $parts[$#parts] eq '' ) { pop @parts; }
            $_one = File::Spec->catdir( $_[1], $parts[$#parts] );
        }
    }
    my $baseend = $_one;
    my $level   = 0;
    my $filen   = 0;
    my $dirn    = 0;

    my $recurs;    #must be my()ed before sub {} since it calls itself
    $recurs = sub {
        my ( $str, $end, $buf ) = @_;
        $filen++ if $end eq $baseend;
        $dirn++  if $end eq $baseend;

        $DirPerms = oct($DirPerms) if substr( $DirPerms, 0, 1 ) eq '0';
        mkdir( $end, $DirPerms ) or return if !-d $end;
        if ( $MaxDepth && $MaxDepth =~ m/^\d+$/ && $level >= $MaxDepth ) {
            chmod scalar( ( stat($str) )[2] ), $end if $KeepMode;
            return ( $filen, $dirn, $level ) if wantarray;
            return $filen;
        }

        $level++;

        my @files;
        if ( $] < 5.006 ) {
            opendir( STR_DH, $str ) or return;
            @files = grep( $_ ne '.' && $_ ne '..', readdir(STR_DH) );
            closedir STR_DH;
        }
        else {
            opendir( my $str_dh, $str ) or return;
            @files = grep( $_ ne '.' && $_ ne '..', readdir($str_dh) );
            closedir $str_dh;
        }

        for my $file (@files) {
            my ($file_ut) = $file =~ m{ (.*) }xms;
            my $org = File::Spec->catfile( $str, $file_ut );
            my $new = File::Spec->catfile( $end, $file_ut );
            if ( -l $org && $CopyLink ) {
                my $target = readlink($org);
                ($target) = $target =~ m/(.*)/;    # mass-untaint is OK since we have to allow what the file system does
                carp "Copying a symlink ($org) whose target does not exist"
                  if !-e $target && $BdTrgWrn;
                unlink $new if -l $new;
                symlink( $target, $new ) or return;
            }
            elsif ( -d $org ) {
                my $rc;
                if ( !-w $org && $KeepMode ) {
                    local $KeepMode = 0;
                    $rc = $recurs->( $org, $new, $buf ) if defined $buf;
                    $rc = $recurs->( $org, $new ) if !defined $buf;
                    chmod scalar( ( stat($org) )[2] ), $new;
                }
                else {
                    $rc = $recurs->( $org, $new, $buf ) if defined $buf;
                    $rc = $recurs->( $org, $new ) if !defined $buf;
                }
                if ( !$rc ) {
                    if ($SkipFlop) {
                        next;
                    }
                    else {
                        return;
                    }
                }
                $filen++;
                $dirn++;
            }
            else {
                if ( $ok_todo_asper_condcopy->($org) ) {
                    if ($SkipFlop) {
                        fcopy( $org, $new, $buf ) or next if defined $buf;
                        fcopy( $org, $new ) or next if !defined $buf;
                    }
                    else {
                        fcopy( $org, $new, $buf ) or return if defined $buf;
                        fcopy( $org, $new ) or return if !defined $buf;
                    }
                    chmod scalar( ( stat($org) )[2] ), $new if $KeepMode;
                    $filen++;
                }
            }
        }
        $level--;
        chmod scalar( ( stat($str) )[2] ), $end if $KeepMode;
        1;

    };

    $recurs->( $_zero, $_one, $_[2] ) or return;
    return wantarray ? ( $filen, $dirn, $level ) : $filen;
}

sub fmove { $move->( 1, @_ ) }

sub rmove {
    if ( -l $_[0] && $CopyLink ) {
        goto &fmove;
    }

    goto &dirmove if -d $_[0] || substr( $_[0], ( 1 * -1 ), 1 ) eq '*';
    goto &fmove;
}

sub rmove_glob {
    $glob->( \&rmove, @_ );
}

sub dirmove { $move->( 0, @_ ) }

sub pathmk {
    my ( $vol, $dir, $file ) = File::Spec->splitpath( shift() );
    my $nofatal = shift;

    $DirPerms = oct($DirPerms) if substr( $DirPerms, 0, 1 ) eq '0';

    if ( defined($dir) ) {
        my (@dirs) = File::Spec->splitdir($dir);

        for ( my $i = 0; $i < scalar(@dirs); $i++ ) {
            my $newdir = File::Spec->catdir( @dirs[ 0 .. $i ] );
            my $newpth = File::Spec->catpath( $vol, $newdir, "" );

            mkdir( $newpth, $DirPerms ) or return if !-d $newpth && !$nofatal;
            mkdir( $newpth, $DirPerms ) if !-d $newpth && $nofatal;
        }
    }

    if ( defined($file) ) {
        my $newpth = File::Spec->catpath( $vol, $dir, $file );

        mkdir( $newpth, $DirPerms ) or return if !-d $newpth && !$nofatal;
        mkdir( $newpth, $DirPerms ) if !-d $newpth && $nofatal;
    }

    1;
}

sub pathempty {
    my $pth = shift;

    my ( $orig_dev, $orig_ino ) = ( lstat $pth )[ 0, 1 ];
    return 2 if !-d _ || !defined($orig_dev) || ( $^O ne 'MSWin32' && !$orig_ino );    #stat.inode is 0 on Windows

    my $starting_point = Cwd::cwd();
    my ( $starting_dev, $starting_ino ) = ( lstat $starting_point )[ 0, 1 ];
    chdir($pth) or Carp::croak("Failed to change directory to “$pth”: $!");
    $pth = '.';
    _bail_if_changed( $pth, $orig_dev, $orig_ino );

    my @names;
    my $pth_dh;
    if ( $] < 5.006 ) {
        opendir( PTH_DH, $pth ) or return;
        @names = grep !/^\.\.?$/, readdir(PTH_DH);
        closedir PTH_DH;
    }
    else {
        opendir( $pth_dh, $pth ) or return;
        @names = grep !/^\.\.?$/, readdir($pth_dh);
        closedir $pth_dh;
    }
    _bail_if_changed( $pth, $orig_dev, $orig_ino );

    for my $name (@names) {
        my ($name_ut) = $name =~ m{ (.*) }xms;
        my $flpth = File::Spec->catdir( $pth, $name_ut );

        if ( -l $flpth ) {
            _bail_if_changed( $pth, $orig_dev, $orig_ino );
            unlink $flpth or return;
        }
        elsif ( -d $flpth ) {
            _bail_if_changed( $pth, $orig_dev, $orig_ino );
            pathrmdir($flpth) or return;
        }
        else {
            _bail_if_changed( $pth, $orig_dev, $orig_ino );
            unlink $flpth or return;
        }
    }

    chdir($starting_point) or Carp::croak("Failed to change directory to “$starting_point”: $!");
    _bail_if_changed( ".", $starting_dev, $starting_ino );

    return 1;
}

sub pathrm {
    my ( $path, $force, $nofail ) = @_;

    my ( $orig_dev, $orig_ino ) = ( lstat $path )[ 0, 1 ];
    return 2 if !-d _ || !defined($orig_dev) || !$orig_ino;

    # Manual test (I hate this function :/):
    #    sudo mkdir /foo && perl -MFile::Copy::Recursive=pathrm -le 'print pathrm("/foo",1)' && sudo rm -rf /foo
    if ( $force && File::Spec->file_name_is_absolute($path) ) {
        Carp::croak("pathrm() w/ force on abspath is not allowed");
    }

    my @pth = File::Spec->splitdir($path);

    my %fs_check;
    my $aggregate_path;
    for my $part (@pth) {
        $aggregate_path = defined $aggregate_path ? File::Spec->catdir( $aggregate_path, $part ) : $part;
        $fs_check{$aggregate_path} = [ ( lstat $aggregate_path )[ 0, 1 ] ];
    }

    while (@pth) {
        my $cur = File::Spec->catdir(@pth);
        last if !$cur;    # necessary ???

        if ($force) {
            _bail_if_changed( $cur, $fs_check{$cur}->[0], $fs_check{$cur}->[1] );
            if ( !pathempty($cur) ) {
                return unless $nofail;
            }
        }
        _bail_if_changed( $cur, $fs_check{$cur}->[0], $fs_check{$cur}->[1] );
        if ($nofail) {
            rmdir $cur;
        }
        else {
            rmdir $cur or return;
        }
        pop @pth;
    }

    return 1;
}

sub pathrmdir {
    my $dir = shift;
    if ( -e $dir ) {
        return if !-d $dir;
    }
    else {
        return 2;
    }

    my ( $orig_dev, $orig_ino ) = ( lstat $dir )[ 0, 1 ];
    return 2 if !defined($orig_dev) || ( $^O ne 'MSWin32' && !$orig_ino );

    pathempty($dir) or return;
    _bail_if_changed( $dir, $orig_dev, $orig_ino );
    rmdir $dir or return;

    return 1;
}

sub _bail_if_changed {
    my ( $path, $orig_dev, $orig_ino ) = @_;

    my ( $cur_dev, $cur_ino ) = ( lstat $path )[ 0, 1 ];

    if ( !defined $cur_dev || !defined $cur_ino ) {
        $cur_dev ||= "undef(path went away?)";
        $cur_ino ||= "undef(path went away?)";
    }
    else {
        $path = Cwd::abs_path($path);
    }

    if ( $orig_dev ne $cur_dev || $orig_ino ne $cur_ino ) {
        local $Carp::CarpLevel += 1;
        Carp::croak("directory $path changed: expected dev=$orig_dev ino=$orig_ino, actual dev=$cur_dev ino=$cur_ino, aborting");
    }
}

1;

__END__

=head1 NAME

File::Copy::Recursive - Perl extension for recursively copying files and directories

=head1 SYNOPSIS

  use File::Copy::Recursive qw(fcopy rcopy dircopy fmove rmove dirmove);

  fcopy($orig,$new[,$buf]) or die $!;
  rcopy($orig,$new[,$buf]) or die $!;
  dircopy($orig,$new[,$buf]) or die $!;

  fmove($orig,$new[,$buf]) or die $!;
  rmove($orig,$new[,$buf]) or die $!;
  dirmove($orig,$new[,$buf]) or die $!;
  
  rcopy_glob("orig/stuff-*", $trg [, $buf]) or die $!;
  rmove_glob("orig/stuff-*", $trg [,$buf]) or die $!;

=head1 DESCRIPTION

This module copies and moves directories recursively (or single files, well... singley) to an optional depth and attempts to preserve each file or directory's mode.

=head1 EXPORT

None by default. But you can export all the functions as in the example above and the path* functions if you wish.

=head2 fcopy()

This function uses File::Copy's copy() function to copy a file but not a directory. Any directories are recursively created if need be.
One difference to File::Copy::copy() is that fcopy attempts to preserve the mode (see Preserving Mode below)
The optional $buf in the synopsis is the same as File::Copy::copy()'s 3rd argument.
This function returns the same as File::Copy::copy() in scalar context and 1,0,0 in list context to accomodate rcopy()'s list context on regular files. (See below for more info)

=head2 dircopy()

This function recursively traverses the $orig directory's structure and recursively copies it to the $new directory.
$new is created if necessary (multiple non existent directories is ok (i.e. foo/bar/baz). The script logically and portably creates all of them if necessary).
It attempts to preserve the mode (see Preserving Mode below) and 
by default it copies all the way down into the directory (see Managing Depth, below).
If a directory is not specified it croaks just like fcopy croaks if its not a file that is specified.

This function returns true or false: for true in scalar context it returns the number of files and directories copied,
whereas in list context it returns the number of files and directories, number of directories only, depth level traversed.

  my $num_of_files_and_dirs = dircopy($orig,$new);
  my($num_of_files_and_dirs,$num_of_dirs,$depth_traversed) = dircopy($orig,$new);
  
Normally it stops and returns if a copy fails. To continue on regardless, set $File::Copy::Recursive::SkipFlop to true.

    local $File::Copy::Recursive::SkipFlop = 1;

That way it will copy everythging it can in a directory and won't stop because of permissions, etc...

=head2 rcopy()

This function will allow you to specify a file *or* a directory. It calls fcopy() if you passed file and dircopy() if you passed a directory.
If you call rcopy() (or fcopy() for that matter) on a file in list context, the values will be 1,0,0 since no directories and no depth are used. 
This is important because if it's a directory in list context and there is only the initial directory the return value is 1,1,1.

=head2 rcopy_glob()

This function lets you specify a pattern suitable for perl's File::Glob::bsd_glob() as the first argument. Subsequently each path returned by perl's File::Glob::bsd_glob() gets rcopy()ied.

It returns and array whose items are array refs that contain the return value of each rcopy() call.

It forces behavior as if $File::Copy::Recursive::CPRFComp is true.

=head2 fmove()

Copies the file then removes the original. You can manage the path the original file is in according to $RemvBase.

=head2 dirmove()

Uses dircopy() to copy the directory then removes the original. You can manage the path the original directory is in according to $RemvBase.

=head2 rmove()

Like rcopy() but calls fmove() or dirmove() instead.

=head2 rmove_glob()

Like rcopy_glob() but calls rmove() instead of rcopy()

=head3 $RemvBase

Default is false. When set to true the *move() functions will not only attempt to remove the original file or directory but will remove the given path it is in.

So if you:

   rmove('foo/bar/baz', '/etc/');
   # "baz" is removed from foo/bar after it is successfully copied to /etc/
   
   local $File::Copy::Recursive::Remvbase = 1;
   rmove('foo/bar/baz','/etc/');
   # if baz is successfully copied to /etc/ :
   # first "baz" is removed from foo/bar
   # then "foo/bar is removed via pathrm()

=head4 $ForcePth

Default is false. When set to true it calls pathempty() before any directories are removed to empty the directory so it can be rmdir()'ed when $RemvBase is in effect.

=head2 Creating and Removing Paths

=head3 $NoFtlPth

Default is false. If set to true  rmdir(), mkdir(), and pathempty() calls in pathrm() and pathmk() do not return() on failure.

If its set to true they just silently go about their business regardless. This isn't a good idea but it's there if you want it.

=head3 $DirPerms

Mode to pass to any mkdir() calls. Defaults to 0777 as per umask()'s POD. Explicitly having this allows older perls to be able to use FCR and might add a bit of flexibility for you.

Any value you set it to should be suitable for oct().

=head3 Path functions

These functions exist solely because they were necessary for the move and copy functions to have the features they do and not because they are of themselves the purpose of this module. That being said, here is how they work so you can understand how the copy and move functions work and use them by themselves if you wish.

=head4 pathrm()

Removes a given path recursively. It removes the *entire* path so be careful!!!

Returns 2 if the given path is not a directory.

  File::Copy::Recursive::pathrm('foo/bar/baz') or die $!;
  # foo no longer exists

Same as:

  rmdir 'foo/bar/baz' or die $!;
  rmdir 'foo/bar' or die $!;
  rmdir 'foo' or die $!;

An optional second argument makes it call pathempty() before any rmdir()'s when set to true.

  File::Copy::Recursive::pathrm('foo/bar/baz', 1) or die $!;
  # foo no longer exists

Same as:PFSCheck

  File::Copy::Recursive::pathempty('foo/bar/baz') or die $!;
  rmdir 'foo/bar/baz' or die $!;
  File::Copy::Recursive::pathempty('foo/bar/') or die $!;
  rmdir 'foo/bar' or die $!;
  File::Copy::Recursive::pathempty('foo/') or die $!;
  rmdir 'foo' or die $!;

An optional third argument acts like $File::Copy::Recursive::NoFtlPth, again probably not a good idea.

=head4 pathempty()

Recursively removes the given directory's contents so it is empty. Returns 2 if the given argument is not a directory, 1 on successfully emptying the directory.

   File::Copy::Recursive::pathempty($pth) or die $!;
   # $pth is now an empty directory

=head4 pathmk()

Creates a given path recursively. Creates foo/bar/baz even if foo does not exist.

   File::Copy::Recursive::pathmk('foo/bar/baz') or die $!;

An optional second argument if true acts just like $File::Copy::Recursive::NoFtlPth, which means you'd never get your die() if something went wrong. Again, probably a *bad* idea.

=head4 pathrmdir()

Same as rmdir() but it calls pathempty() first to recursively empty it first since rmdir can not remove a directory with contents.
Just removes the top directory the path given instead of the entire path like pathrm(). Returns 2 if the given argument does not exist (i.e. it's already gone). Returns false if it exists but is not a directory.

=head2 Preserving Mode

By default a quiet attempt is made to change the new file or directory to the mode of the old one.
To turn this behavior off set
  $File::Copy::Recursive::KeepMode
to false;

=head2 Managing Depth

You can set the maximum depth a directory structure is recursed by setting:
  $File::Copy::Recursive::MaxDepth 
to a whole number greater than 0.

=head2 SymLinks

If your system supports symlinks then symlinks will be copied as symlinks instead of as the target file.
Perl's symlink() is used instead of File::Copy's copy().
You can customize this behavior by setting $File::Copy::Recursive::CopyLink to a true or false value.
It is already set to true or false depending on your system's support of symlinks so you can check it with an if statement to see how it will behave:

    if($File::Copy::Recursive::CopyLink) {
        print "Symlinks will be preserved\n";
    } else {
        print "Symlinks will not be preserved because your system does not support it\n";
    }

If symlinks are being copied you can set $File::Copy::Recursive::BdTrgWrn to true to make it carp when it copies a link whose target does not exist. It's false by default.

    local $File::Copy::Recursive::BdTrgWrn  = 1;

=head2 Removing existing target file or directory before copying.

This can be done by setting $File::Copy::Recursive::RMTrgFil or $File::Copy::Recursive::RMTrgDir for file or directory behavior respectively.

0 = off (This is the default)

1 = carp() $! if removal fails

2 = return if removal fails

    local $File::Copy::Recursive::RMTrgFil = 1;
    fcopy($orig, $target) or die $!;
    # if it fails it does warn() and keeps going

    local $File::Copy::Recursive::RMTrgDir = 2;
    dircopy($orig, $target) or die $!;
    # if it fails it does your "or die"

This should be unnecessary most of the time but it's there if you need it :)

=head2 Turning off stat() check

By default the files or directories are checked to see if they are the same (i.e. linked, or two paths (absolute/relative or different relative paths) to the same file) by comparing the file's stat() info. 
It's a very efficient check that croaks if they are and shouldn't be turned off but if you must for some weird reason just set $File::Copy::Recursive::PFSCheck to a false value. ("PFS" stands for "Physical File System")

=head2 Emulating cp -rf dir1/ dir2/

By default dircopy($dir1,$dir2) will put $dir1's contents right into $dir2 whether $dir2 exists or not.

You can make dircopy() emulate cp -rf by setting $File::Copy::Recursive::CPRFComp to true.

NOTE: This only emulates -f in the sense that it does not prompt. It does not remove the target file or directory if it exists.
If you need to do that then use the variables $RMTrgFil and $RMTrgDir described in "Removing existing target file or directory before copying" above.

That means that if $dir2 exists it puts the contents into $dir2/$dir1 instead of $dir2 just like cp -rf.
If $dir2 does not exist then the contents go into $dir2 like normal (also like cp -rf).

So assuming 'foo/file':

    dircopy('foo', 'bar') or die $!;
    # if bar does not exist the result is bar/file
    # if bar does exist the result is bar/file

    $File::Copy::Recursive::CPRFComp = 1;
    dircopy('foo', 'bar') or die $!;
    # if bar does not exist the result is bar/file
    # if bar does exist the result is bar/foo/file

You can also specify a star for cp -rf glob type behavior:

    dircopy('foo/*', 'bar') or die $!;
    # if bar does not exist the result is bar/file
    # if bar does exist the result is bar/file

    $File::Copy::Recursive::CPRFComp = 1;
    dircopy('foo/*', 'bar') or die $!;
    # if bar does not exist the result is bar/file
    # if bar does exist the result is bar/file

NOTE: The '*' is only like cp -rf foo/* and *DOES NOT EXPAND PARTIAL DIRECTORY NAMES LIKE YOUR SHELL DOES* (i.e. not like cp -rf fo* to copy foo/*).

=head2 Allowing Copy Loops

If you want to allow:

  cp -rf . foo/

type behavior set $File::Copy::Recursive::CopyLoop to true.

This is false by default so that a check is done to see if the source directory will contain the target directory and croaks to avoid this problem.

If you ever find a situation where $CopyLoop = 1 is desirable let me know. (i.e. it's a bad bad idea but is there if you want it)

(Note: On Windows this was necessary since it uses stat() to determine sameness and stat() is essentially useless for this on Windows. 
The test is now simply skipped on Windows but I'd rather have an actual reliable check if anyone in Microsoft land would care to share)

=head1 SEE ALSO

L<File::Copy> L<File::Spec>

=head1 TO DO

I am currently working on and reviewing some other modules to use in the new interface so we can lose the horrid globals as well as some other undesirable traits and also more easily make available some long standing requests.

Tests will be easier to do with the new interface and hence the testing focus will shift to the new interface and aim to be comprehensive.

The old interface will work, it just won't be brought in until it is used, so it will add no overhead for users of the new interface.

I'll add this after the latest version has been out for a while with no new features or issues found :)

=head1 AUTHOR

Daniel Muey, L<http://drmuey.com/cpan_contact.pl>

=head1 COPYRIGHT AND LICENSE

Copyright 2004 by Daniel Muey

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut

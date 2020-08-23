package App::cpm::Worker::Resolver;
use strict;
use warnings;

use App::cpm::Logger::File;

sub new {
    my ($class, %option) = @_;
    my $logger = $option{logger} || App::cpm::Logger::File->new;
    bless { impl => $option{impl}, logger => $logger }, $class;
}

sub work {
    my ($self, $job) = @_;

    local $self->{logger}->{context} = $job->{package};
    my $result = $self->{impl}->resolve($job);
    if ($result and !$result->{error}) {
        $result->{ok} = 1;
        my $msg = sprintf "Resolved %s (%s) -> %s", $job->{package}, $job->{version_range} || 0,
            $result->{uri} . ($result->{from} ? " from $result->{from}" : "");
        $self->{logger}->log($msg);
        return $result;
    } else {
        $self->{logger}->log($result->{error}) if $result and $result->{error};
        $self->{logger}->log(sprintf "Failed to resolve %s", $job->{package});
        return { ok => 0 };
    }
}

1;

use warnings;
use strict;
use YAML::XS 'LoadFile';
use feature 'say';
use Switch;
use IO::Socket;
use Digest::MD5 qw(md5);
use File::Slurp;
use Data::Dump qw(dump);

my $config = LoadFile('config.yaml');
if (!$config) {
    say "error: unable to find config.yaml";
    exit 1;
}

$config = $config->{"kubycat"};
if (!$config) {
    say "error: no configuration found in config.yaml";
    exit 1;
}

# Server port number
my $port = $config->{"port"};
if (!$port) {
    say "error: kubycat.port not set in config.yaml";
    exit 1;
}

# Kubernetes context
my $kube_context = $config->{"context"};

# Kubernetes global namesapce
my $kube_global_namespace = $config->{"namespace"};

# Sync definitions
my @syncs = @{$config->{"sync"}};

if (@syncs == 0) {
    say "warning: no syncs defined in kubycat.sync";
    exit 1;
}


my $command = $ARGV[0];

switch($command) {
    case "watch" {
    # Start the Server
    my %file_digests = ();
    my $socket = new IO::Socket::INET (
        LocalHost => 'localhost',
        LocalPort => $port,
        Proto => 'tcp',
        Listen => 1,
        Reuse => 1,
    );
    die "error: failed to start server on port $port" unless $socket;

    # Start Watching
    my @watches = ();
    foreach ( @syncs ) {
        my %sync_config = %$_;
        my $name = $sync_config{"name"};
        my $base = $sync_config{"base"};
        my $namespace = $sync_config{"namespace"};
        my @froms = @{$sync_config{"from"}};
        my $to = $sync_config{"to"};
        my $pod = $sync_config{"pod"};
        my $pod_label = $sync_config{"pod-label"};

        if (!$pod && !$pod_label) {
            say "error: use of sync without pod or pod-label set";
            exit 1;
        }

        my @resolved_froms = ();
        foreach my $from ( @froms ) {
            my $relative = substr($from, 0, 1) ne "/";
            if ($relative && !$base) {
                say "error: use of relative path $from without base path set";
                exit 1;
            }
            my $file;
            if ($relative) {
                $file = "$base/$from";
            } else {
                $file = $from;
            }
            push (@resolved_froms, $file);
            push (@watches, $file);
        }
        $sync_config{"from"} = @resolved_froms;
    }

        my $command =
"fswatch " . join(" ", @watches) . " \\
    -r \\
    --event Created \\
    --event Updated \\
    --event Removed \\
    --event Renamed \\
    --event MovedFrom \\
    --event MovedTo \\
    --event OwnerModified \\
    --event AttributeModified \\
    --latency 3 \\
| xargs -I {} perl ./kubycat.pl sync {} &";
        say $command;
        system($command);

        # wait for connections
        print "listening to localhost on port $port...\n";
        while (1) {
        my $new_socket = $socket->accept();
        while(<$new_socket>)
        {
            my $file = $_;
            if(!stat($file)) {
                my $status = $file_digests{$file};
                if ($status eq "DELETED") {
                    `echo SKIP-DELETE:$file >> sync.log`;
                } else {
                    `echo DELETE:$file >> sync.log`;
                    $file_digests{$file} = "DELETED";
                }
            } else {
                my $data = read_file($file);
                my $digest = md5($data);
                my $old_digest = $file_digests{$file};
                if ($old_digest && $digest && $old_digest eq $digest) {
                    # do nothing
                    `echo SKIP-COPY:$file >> sync.log`;
                } else {
                    `echo COPY:$file >> sync.log`;
                    $file_digests{$file} = $digest;
                }
            }
        }
    }
    }
    case "sync" {
        my $socket = new IO::Socket::INET (
            PeerAddr => 'localhost',
            PeerPort => $port,
            Proto => 'tcp',
        );
        die "error: failed to connect to server on port $port" unless $socket;
        print $socket $ARGV[1];
    }
    else {
        say "error: kubycat only supports the 'watch' and 'sync' commands.";
        exit 1;
    }
}

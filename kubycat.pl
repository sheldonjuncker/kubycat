use warnings;
use strict;
use experimental 'smartmatch';
use YAML::XS 'LoadFile';
use feature 'say';
use Switch;
use IO::Socket;
use Digest::MD5 qw(md5);
use File::Slurp;
use Data::Dump qw(dump);

my $version = "0.0.1";

my $config = LoadFile('/etc/kubycat/config.yaml');
if (!$config) {
    say "error: unable to find config.yaml\n";
    exit 1;
}

$config = $config->{"kubycat"};
if (!$config) {
    say "error: no configuration found in config.yaml\n";
    exit 1;
}

# Server port number
my $port = $config->{"port"};
if (!$port) {
    say "error: kubycat.port not set in config.yaml\n";
    exit 1;
}

# Kubernetes config file
my $kube_global_config = $config->{"config"};

# Kubernetes context
my $kube_global_context = $config->{"context"};

# Kubernetes global namesapce
my $kube_global_namespace = $config->{"namespace"};

# Sync definitions
my @syncs = @{$config->{"sync"}};

if (@syncs == 0) {
    say "warning: no syncs defined in kubycat.sync\n";
    exit 0;
}

my %file_digests = ();
my @resolved_syncs = ();

my $command = $ARGV[0];

sub get_file_status {
    my $file = shift;
    my @file_stat = stat($file);
    if(@file_stat == 0) {
        my $status = $file_digests{$file};
        if ($status and $status eq "DELETED") {
            return 'UNCHANGED';
        } else {
            $file_digests{$file} = "DELETED";
            return 'DELETED';
        }
    } else {
        # Only sync a file if either it's content hash or ctime has changed
        # (note: ctime can actually change without contents/metadata really changing
        # i.e. when a file is saved with the same contents, it's technically "modified" and "changed")
        my $ctime = $file_stat[10];
        my $data = read_file($file);
        my $digest = md5($data . $ctime);
        my $old_digest = $file_digests{$file};
        if ($old_digest && $digest && $old_digest eq $digest) {
            return 'UNCHANGED';
        } else {
            $file_digests{$file} = $digest;
            return 'CHANGED';
        }
    }
}

switch($command) {
    case "version" {
        say "kubycat version $version";
        say "written by Sheldon Juncker <sheldon\@dreamcloud.app>";
    }
    case "watch" {
        # Start the Server
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
            my $kube_config = $sync_config{"config"};
            my $kube_context = $sync_config{"context"};
            my @froms = @{$sync_config{"from"}};
            my $to = $sync_config{"to"};
            my $pod = $sync_config{"pod"};
            my $pod_label = $sync_config{"pod-label"};
            my $shell = $sync_config{"shell"};

            if (!$namespace && $kube_global_namespace) {
                $namespace = $kube_global_namespace;
            }
            if (!$namespace) {
                say "error: either a global namespace or sync namespace must be set\n";
                exit 1;
            }
            $sync_config{"namespace"} = $namespace;

            if (!$kube_config && $kube_global_config) {
                $kube_config = $kube_global_config;
            }
            $sync_config{"config"} = $kube_config;

            if (!$kube_context && $kube_global_context) {
                $kube_context = $kube_global_context;
            }
            $sync_config{"context"} = $kube_context;

            if (!$base) {
                say "error: use of sync without base path set\n";
                exit 1;
            }
            if (!(substr($base, 0, 1) ~~ ["/", "\\"])) {
                say "error: use of relative path within base is not allowed\n";
                exit;
            }

            if ($to && !(substr($to, 0, 1) ~~ ["/", "\\"])) {
                say "error: use of relative path within to is not allowed\n";
                exit;
            }

            if (!$pod && !$pod_label && $to) {
                say "error: use of sync.to without pod or pod-label set\n";
                exit 1;
            }

            if ($to && !$shell) {
                say "error: use of sync.to without shell set\n";
                exit 1;
            }

            my @resolved_froms = ();
            foreach my $from ( @froms ) {
                if (substr($from, 0, 1) ~~ ["/", "\\"]) {
                    say "error: use of absolute path in sync.from is not allowed\n";
                    exit 1;
                }
                my $file = "$base/$from";
                push (@resolved_froms, $file);
                push (@watches, $file);
            }
            $sync_config{"from"} = [@resolved_froms];
            push(@resolved_syncs, { %sync_config });
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
| xargs -I {} kubycat sync {} &";
        say $command;
        system($command);

        # wait for connections
        print "listening to localhost on port $port...\n";
        while (1) {
            my $new_socket = $socket->accept();
            while(<$new_socket>)
            {
                my $file = $_;
                my %sync = get_sync($file);
                if (!%sync) {
                    say "warning: could not find sync for file $file\n";
                    next;
                }

                my $status = get_file_status($file);
                if ($status eq 'UNCHANGED') {
                    say "UNCHANGED:$file";
                    next;
                }

                say "CHANGED:$file";

                my $to = $sync{"to"};
                if ($to) {
                    if ($status eq 'DELETED') {
                        say "SYNC-DELETE:$file";
                        delete_file($file, { %sync });
                        next;
                    } else {
                        say "SYNC-UPDATE:$file";
                        copy_file($file, { %sync });
                    }
                }

                # After sync/change, run local and remote commands if defined
                if ($status ne 'UNCHANGED') {
                    my $post_sync_remote = $sync{"post-sync-remote"};
                    my $post_sync_local = $sync{"post-sync-local"};

                    if ($post_sync_remote) {
                        say "POST-SYNC-REMOTE:$file";
                        my $kubectl = get_kubectl_delete_command(%sync);
                        my @pods = get_pods(%sync);
                        foreach my $pod (@pods) {
                            my $command = "$kubectl $pod -- $post_sync_remote";
                            say "$command\n";
                            system($command);
                        }
                    }

                    if ($post_sync_local) {
                        if ($post_sync_local eq "kubycat::exit") {
                            say "exiting kubycat...";
                            exit 0;
                        }
                        say "POST-SYNC-LOCAL:$file";
                        say "$post_sync_local\n";
                        system($post_sync_local);
                    }
                }
            }
        }
    }
    case "sync" {
        my $file = $ARGV[1];
        say "SYNC:$file";
        my $socket = new IO::Socket::INET (
            PeerAddr => 'localhost',
            PeerPort => $port,
            Proto => 'tcp',
        );
        die "error: failed to connect to server on port $port" unless $socket;
        print $socket $file;
    }
    case "help" {
        help();
        exit 0;
    }
    else {
        help();
        exit 1;
    }
}

sub help {
    say "usage: kubycat.pl watch|sync [options]";
}

sub get_kubectl_delete_command {
    my %sync = @_;
    my $command = "kubectl exec ";

    my $kube_context = $sync{"context"};
    if ($kube_context) {
        $command .= " --context $kube_context";
    }

    my $kube_config = $sync{"config"};
    if ($kube_config) {
        $command .= " --kube-config $kube_config";
    }

    my $namespace = $sync{"namespace"};
    $command .= " --namespace $namespace";

    return $command;
}

sub get_kubectl_copy_command {
    my %sync = @_;
    my $command = "kubectl cp";

    my $kube_context = $sync{"context"};
    if ($kube_context) {
        $command .= " --context $kube_context";
    }

    my $kube_config = $sync{"config"};
    if ($kube_config) {
        $command .= " --kube-config $kube_config";
    }

    return $command;
}

sub get_kubectl_pods_command {
    # kubectl get pods -n elsewhere -l tier=php -o custom-columns=NAME:.metadata.name --no-headers
    my %sync = @_;
    my $command = "kubectl get pods";

    my $kube_context = $sync{"context"};
    if ($kube_context) {
        $command .= " --context $kube_context";
    }

    my $kube_config = $sync{"config"};
    if ($kube_config) {
        $command .= " --kube-config $kube_config";
    }

    $command .= " --namespace " . $sync{"namespace"};
    $command .= " -l " . $sync{"pod-label"};
    $command .= " -o custom-columns=NAME:.metadata.name --no-headers";
    return $command;
}

sub get_pods {
    my %sync = @_;
    my $pod = $sync{"pod"};
    my $label = $sync{"label"};
    if ($pod) {
        return ($pod);
    } else {
        my $command = get_kubectl_pods_command(%sync);
        say "$command\n";
        my @pods = `$command`;
        chomp @pods;
        return @pods;
    }
}

# Deletes a file in the Kubernetes cluster
sub delete_file {
    my $file = $_[0];
    my %sync = %{$_[1]};
    my $kubectl = get_kubectl_delete_command(%sync);
    my $shell = $sync{"shell"};
    my $base = $sync{"base"};
    my $to = $sync{"to"};
    my $relative_file = substr($file, length($base) + 1);
    my $remote_file = "$to/$relative_file";
    my @pods = get_pods(%sync);
    foreach my $pod (@pods) {
        my $command = "$kubectl $pod -- $shell -c \"rm -Rf $remote_file\"";
        say "$command\n";
        system($command);
    }
}

sub copy_file {
    my $file = $_[0];
    my %sync = %{$_[1]};
    my $namespace = $sync{"namespace"};
    my $kubectl = get_kubectl_copy_command(%sync);
    my $shell = $sync{"shell"};
    my $base = $sync{"base"};
    my $to = $sync{"to"};
    my $relative_file = substr($file, length($base) + 1);
    my $remote_file = "$to/$relative_file";
    my @pods = get_pods(%sync);
    foreach my $pod (@pods) {
        my $command = "$kubectl $file $namespace/$pod:$remote_file";
        say "$command\n";
        system($command);
    }
}

sub get_sync {
    my $file = $_[0];
    foreach ( @resolved_syncs ) {
        my %sync_config = %$_;
        my @froms = @{$sync_config{"from"}};
        foreach my $from (@froms) {
            # if the file is exactly what we are looking for
            # or if the file is deeper inside of the sync path
            # the first one wins--not the closest one
            if ($file eq $from or ($from eq substr($file, 0, length($from)) and substr($file, length($from), 1) ~~ ["/", "\\"])) {
                return %sync_config;
            }
        }
    }
    return ();
}

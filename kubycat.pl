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
use File::Basename;

my $header = "+---------+--------+----------------------------------------------------+------------+";

my $fswatch_command;

$SIG{TERM} = sub { kubycat_exit(0); };

# get the location of the currently executing script
my $script_path = dirname(__FILE__);
my $kubycat_command = "$script_path/kubycat";

sub kubycat_exit {
    my $status = shift;
    # Kill all child processes and wait for them to exit
    say_status("KUBYCAT", "EXIT","Received SIGTERM and stopping services...", "EXITING");
    # get the PID based on the KUBYCAT_PID flag
    say_status("FSWATCH", "EXIT", "Shutting down fswatch daemon...", "EXITING");
    my $find_fswatch = "ps ax | grep -oP \"\\s*\\K([0-9]+)(?=.+" . quotemeta($fswatch_command) . ")\"";
    say "| $find_fswatch";
    my @fswatch_matches = `$find_fswatch`;
    my $fswatch_pid = shift @fswatch_matches;
    if ($fswatch_pid) {
        say "| kill $fswatch_pid";
        system("kill $fswatch_pid");
        say_status("FSWATCH", "EXIT", "Shutting down fswatch daemon...", "SUCCESS");
    } else {
        say_status("FSWATCH", "EXIT", "Shutting down fswatch daemon...", "NO_DAEMON");
    }
    say_status("KUBYCAT", "EXIT", "Shutting down kubycat daemon...", "SUCCESS");
    exit $status;
};

my $version = "0.1.6";

# read the --config argument
my $config_file = "/etc/kubycat/config.yaml";
for (my $i = 0; $i < @ARGV; $i++) {
    if ($ARGV[$i] eq "--config") {
        $config_file = $ARGV[$i + 1];
        splice(@ARGV, $i, 2);
        last;
    }
}

my $config = LoadFile($config_file);
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

# Kubernetes config file
my $kube_global_config = $config->{"config"};

# Kubernetes context
my $kube_global_context = $config->{"context"};

# Kubernetes global namesapce
my $kube_global_namespace = $config->{"namespace"};

# Sync definitions
my @syncs = @{$config->{"sync"}};

if (@syncs == 0) {
    say "warning: no syncs defined in kubycat.sync";
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
        my $digest;
        if ($file_stat[2] & 0040000) {
            # if the file is a directory, we can't really read it's contents so just use the ctime
            $digest = md5($ctime);
        } else {
            my $data = read_file($file);
            $digest = md5($data . $ctime);
        }
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
        say "starting kubycat version $version...\n";

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
            my $notify = $sync_config{"notify"};

            if (!$namespace && $kube_global_namespace) {
                $namespace = $kube_global_namespace;
            }
            if (!$namespace) {
                say "error: either a global namespace or sync namespace must be set";
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
                say "error: use of sync without base path set";
                exit 1;
            }
            if (!(substr($base, 0, 1) ~~ ["/", "\\"])) {
                say "error: use of relative path within base is not allowed";
                exit;
            }

            if ($to && !(substr($to, 0, 1) ~~ ["/", "\\"])) {
                say "error: use of relative path within to is not allowed";
                exit;
            }

            if (!$pod && !$pod_label && $to) {
                say "error: use of sync.to without pod or pod-label set";
                exit 1;
            }

            if ($pod && $pod_label) {
                say "error: use of both pod and pod-label is not allowed";
                exit 1;
            }

            if ($to && !$shell) {
                say "error: use of sync.to without shell set";
                exit 1;
            }

            if ($notify && $notify ne "notify-send" && $notify ne "display notification") {
                say "error: use of sync.notify with invalid value (must be 'notify-send' or 'display notification')";
                exit 1;
            }

            my @resolved_froms = ();
            foreach my $from ( @froms ) {
                if (substr($from, 0, 1) ~~ ["/", "\\"]) {
                    say "error: use of absolute path in sync.from is not allowed";
                    exit 1;
                }
                my $file = "$base/$from";
                push (@resolved_froms, $file);
                push (@watches, $file);
            }
            $sync_config{"from"} = [@resolved_froms];
            push(@resolved_syncs, { %sync_config });
        }

        # The child process will watch for file changes
        say "watching files...\n";
        $fswatch_command = "fswatch " . join(" ", @watches) . " /KUBYCAT_PID=$$ -r --event Created --event Updated --event Removed --event Renamed --event MovedFrom --event MovedTo --event OwnerModified --event AttributeModified";
        my $command = $fswatch_command . " | xargs -I {} $kubycat_command sync {} &";
        say "$command\n";
        system($command);


        # The parent process will start a server to listen for sync requests
        say "starting server...\n";
        my $socket = new IO::Socket::INET (
            LocalHost => 'localhost',
            LocalPort => $port,
            Proto => 'tcp',
            Listen => 1,
            Reuse => 1,
        );
        die "error: failed to start server on port $port" unless $socket;

        # wait for connections
        say "listening to localhost on port $port\n";

        say "waiting for file changes...";
        say $header;
        say "| command | action |                        file                        |   status   |";
        say $header;

        while (1) {
            my $new_socket = $socket->accept();
            while(<$new_socket>)
            {
                my $file = $_;
                my $command_name = "SYNC";
                my $command_action;
                my $command_status;
                my $command_file = $file;

                my %sync = get_sync($file);
                if (!%sync) {
                    $command_action = "NONE";
                    $command_status = "NO_SYNC";
                    say_status($command_name, $command_action, $command_file, $command_status);
                    next;
                }

                my $base = $sync{"base"};
                $command_file = substr($command_file, length($base) + 1);
                $command_file = $sync{"name"} . ":$command_file";

                my $status = get_file_status($file);
                if ($status eq 'UNCHANGED') {
                    $command_action = "NONE";
                    $command_status = "NO_CHANGE";
                    say_status($command_name, $command_action, $command_file, $command_status);
                    next;
                }

                my $to = $sync{"to"};
                my $remote_file;
                if ($to) {
                    my @sync_result;
                    if ($status eq 'DELETED') {
                        $command_action = "DELETE";
                        @sync_result = delete_file($file, { %sync });
                    } else {
                        $command_action = "COPY";
                        @sync_result = copy_file($file, { %sync });
                    }
                    my $remote_file = $sync_result[1];
                    say_status($command_name, $command_action, $command_file, $sync_result[0] ? "FAILURE" : "SUCCESS");
                    if ($sync_result[0]) {
                        # send desktop notification
                        say "| " . pad_string("culprit: " . $sync_result[2], length($header) - 13) . " |";
                    }
                }

                # After sync/change, run local and remote commands if defined
                my $post_sync_remote = $sync{"post-sync-remote"};
                my $post_sync_local = $sync{"post-sync-local"};

                if ($post_sync_remote && $to && $remote_file) {
                    my $kubectl = get_kubectl_delete_command(%sync);
                    my @pods = get_pods(%sync);
                    foreach my $pod (@pods) {
                        my $command = "$kubectl $pod -- $post_sync_remote";
                        $command =~ s|{synced_file}|$remote_file|g;
                        print "| ";
                        my $result = system($command);
                        say_status("REMOTE", "EXEC", $post_sync_remote, $result == 0 ? "SUCCESS" : "FAILURE");
                    }
                }

                if ($post_sync_local) {
                    if ($post_sync_local eq "kubycat::exit") {
                        kubycat_exit(0);
                    }
                    my $command = $post_sync_local;
                    $command =~ s|{synced_file}|$file|g;
                    print "| ";
                    my $result = system($post_sync_local);
                    say_status("LOCAL", "EXEC", $post_sync_local, $result == 0 ? "SUCCESS" : "FAILURE");
                }
            }
        }
    }
    case "sync" {
        my $file = $ARGV[1];
        my $socket = new IO::Socket::INET (
            PeerAddr => 'localhost',
            PeerPort => $port,
            Proto => 'tcp',
            Timeout => 30,
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

sub say_status {
    my ($command_name, $command_action, $command_file, $command_status) = @_;
    # pad things
    $command_name = pad_string($command_name, 9);
    $command_action = pad_string($command_action, 8);
    if (length($command_file) > 52) {
        $command_file = "..." . substr($command_file, -49);
    }
    $command_file = pad_string($command_file, 52);
    $command_status = pad_string($command_status, 12);
    say "|$command_name|$command_action|$command_file|$command_status|";
    say $header;
}

sub pad_string {
    my ($string, $length) = @_;
    my $padding = $length - length($string);
    return (' ' x ($padding / 2)) . $string . (' ' x ($padding / 2) . (' ' x ($padding % 2)));
}

sub notify_desktop {
    my ($description, $error, $level, $notify_type) = @_;
    my $command;
    if ($notify_type eq "notify-send") {
        $command = "notify-send -u $level -a Kubycat -c error 'Kubycat Error' '$description\n <p><i>$error</i></p>'";
    } elsif ($notify_type eq "display notification") {
        $command = "osascript -e 'display notification \"$description:\n$error\" with title \"Kubycat\" subtitle \"Kubycat Error\"'";
    } else {
        return;
    }
    system($command);
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
        say "| $command";
        my @pods = `$command 2>&1`;
        chomp @pods;

       # make sure each element of the array is a pod
       my $status = 0;
        foreach my $pod (@pods) {
            if ($pod !~ /^[a-z0-9]([a-z0-9\-\.]*[a-z0-9])*$/) {
                $status = 1;
                last;
            }
        }

        if ($status) {
            my $error = pop @pods;
            say "| error: failed to get pods from kubectl";
            say "|   msg: $error";
            $error = $error =~ s/'/\\'/gr;
            if ($sync{"notify"}) {
                notify_desktop("Failed to get pods from kubectl", $error, "critical", $sync{"notify"});
            }
            kubycat_exit(1);
        }
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
        say "| $command";
        my $result = system($command);
        if ($result) {
            return (1, $remote_file, $command);
        }
    }
    return (0, $remote_file, "");
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
        say "| $command";
        my $result = system($command);
        if ($result) {
            return (1, $remote_file, $command);
        }
    }
    return (0, $remote_file, "");
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

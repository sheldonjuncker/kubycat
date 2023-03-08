<a href="https://www.buymeacoffee.com/sheldonjuncker" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" width=150 height=40></a>

[View Kubycat on GitHub](https://github.com/sheldonjuncker/kubycat)

<img src="https://kubycat.info/kubycat.svg" alt="Kubycat" width="75" style="float: right" align="right" />

# kubycat 
A small library for the watching and automated syncing of files into a local or remote Kubernetes cluster.

```perl
my $name = kubycat
my $version = 0.1.6
my $author = Sheldon Juncker <sheldon@dreamcloud.app>
my $github = https://github.com/sheldonjuncker/kubycat
my $license = MIT
```

## Table of Contents
- [Overview](#overview)
- [Installation](#installation)
  - [Install kubectl](#install-kubectl)
  - [Install fswatch](#install-fswatch)
  - [Acquire the Kubycat source code](#acquire-the-kubycat-source-code)
  - [Install Kubycat](#install-kubycat)
- [Configuration](#configuration)
- [Usage](#usage)
  - [Syncing](#syncing)
  - [Manual Syncing](#manual-syncing)
  - [Version](#version)
  - [Help](#help)
- [About](#about)
- [License](#license)

## Overview
Kubycat is a small library for the watching and automated syncing of files into a local or remote Kubernetes cluster.

Kubycat is best suited for local development where it can be used as a simpler alternative to `ksync` or `Skaffold` where you either don't want to install components into your cluster or you don't want to use a complex project setup with a lot of configuration.

Kubycat relies on `fswatch` to watch for file changes and then uses `kubectl cp` and `kubectl exec` to copy or delete the changed files into the specified Kubernetes pod(s).

Kubycat can run as a Linux service to further automate the process.

**Example:**
```yaml
kubycat:
  config: /home/johndoe/.kube/config
  context: do-sfo1-k8s-cluster
  namespace: default
  port: 1273
  sync:
    - name: web-app
      base: /home/johndoe/web-app
      from:
        - src
        - config
        - index.php
        - .env
        - .htaccess
      to: /remote/www
      pod: php-123
      shell: /bin/sh
```

## Installation
Kubycat requires kubectl, fswatch, and Perl 5.10 or higher to be installed on the system.
Most Linux distributions come with Perl pre-installed, but if you are on Windows you will need to install it.
You can view instructions for doing so here: https://learn.perl.org/installing/windows.html

### Install kubectl
Kubycat uses kubectl to connect to the Kubernetes cluster.

You can install kubectl in any OS by following the instructions here: https://kubernetes.io/docs/tasks/tools/install-kubectl/


### Install fswatch
Kubycat uses fswatch to watch for file changes. This is a standard tool and can be installed in any operating system.
```bash
# Linux
$ apt-get install fswatch

# Mac
$ brew install fswatch 

# Windows
$ not supported (it might still work, but it's not tested)
$ explorer "https://github.com/emcrisostomo/fswatch/blob/master/README.windows"
```

### Acquire the Kubycat source code
You can either clone the repository and use the tagged source code directly or you can download the [latest release](https://github.com/sheldonjuncker/kubycat/releases/latest).
```bash
$ git clone https://github.com/sheldonjuncker/kubycat.git
```

### Install Kubycat
Kubycat comes with an install script for Linux/Mac that can do the following:
- Install required Perl modules
- Copy the kubycat scripts to a global location
- Copy the kubycat config file to a global location
- Install kubycat as a systemd service (Linux only)

You can run the installation script as follows:
```bash
$ cd kubycat
$ ./install
```

_Note that the install script requires sudo access to copy the scripts and config file to a global location._

You can alternatively install Kubycat manually by:
1. Installing the Perl modules: `YAML::XS`, `IO::Socket`, `Digest::MD5`, `File::Slurp`, `Switch`, and `Data::Dumper`

Example:
```bash
cpan -i YAML::XS
cpan -i IO::Socket
cpan -i Digest::MD5
cpan -i File::Slurp
cpan -i Data::Dump
cpan -i Switch
```

2. (optional) Adding the kubycat scripts to your path.
Example:
```bash
echo 'export PATH="$PATH:/path/to/kubycat"' >> ~/.bashrc
source ~/.bashrc
```

You can test the installation by running:
```bash
$ kubycat version
```
if installed globally or:
```bash
$ ./kubycat version
```
if otherwise.

If you installed kubycat as a service you might also want to test that it is running:
```bash
$ sudo systemctl --user status kubycat
```

## Configuration
Kubycat is configured via a YAML file which by default is located at `/etc/kubycat/config.yaml` but may differ depending on your installation.

The source code contains this sample configuration providing a brief overview of each available option. More detailed documentation is provided below.
```yaml
kubycat:
  config: /home/johndoe/.kube/config
  context: minikube
  namespace: default
  port: 1273
  sync:
    - name: test
      base: /home/johndoe/test/
      config: /home/johndoe/.kube/do-sfo3-k8s-johndoe
      context: do-sfo3-k8s-johndoe
      namespace: other
      from:
        - src
        - config
        - index.php
      to: /remote/server
      excluding:
        - .+~$
      including:
        - .+\.php$
      pod: pod-name
      pod-label: key=value
      shell: /bin/sh
      notify: notify-send
      on-sync-error: exit
      on-post-sync-error: exit
    - name: composer
      base: /home/johndoe/test/
      namespace: other
      from:
        - composer.json
        - composer.lock
      to: /remote/server
      pod-label: key=value
      shell: /bin/sh
      post-sync-local: composer update
      post-sync-remote: /bin/sh -c "composer install"
```

### kubycat
The `kubycat` section contains all options to configure Kubycat.

### kubycat.config
The `kubycat.config` option specifies the Kubernetes config file to use. This should be an absolute path to the config file, but can be left blank in which case the default config file will be used by kubectl.

You can also override this for any individual sync specification. 

### kubycat.context
The `kubycat.context` option specifies the Kubernetes context to use. This allows you to specify which Kubernetes cluster to connect to while using the same config file.

Like the `kubycat.config` option, this can be left blank or overridden for any individual sync specification.

### kubycat.namespace
The `kubycat.namespace` option specifies the default Kubernetes namespace to sync files into. This can also be left blank to use the default namespace or overridden.

### kubycat.port
The `kubycat.port` option specifies the port to use for the kubycat file syncing server.

### kubycat.sync
The `kubycat.sync` option is a list of sync specifications. Each sync specification contains the following options:

### kubycat.sync.name
The `kubycat.sync.name` option specifies the name of the sync. This is currently not used except to make the YAML look prettier and can be anything.

### kubycat.sync.base
The `kubycat.sync.base` option specifies the base directory to sync from. This must be an absolute path, from which the individual `from` paths will be resolved.

### kubycat.sync.namespace
The `kubycat.sync.namespace` option specifies the Kubernetes namespace to sync files into. This can be left blank to use the global or default namespace.

### kubycat.sync.config
The `kubycat.sync.config` option specifies the Kubernetes config file to use for this sync. This should be an absolute path to the config file, but can be left blank in which case the global or default config will be used.

### kubycat.sync.context
The `kubycat.sync.context` option specifies the Kubernetes context to use for this sync. This can be left blank to use the global or default context.

### kubycat.sync.from
The `kubycat.sync.from` option is a list of files and/or folders to sync from the `base` directory. This can be a single file or folder or a list of files and folders. Each path must be a relative path from the `base` directory and if a folder will be synced recursively.

### kubycat.sync.excluding
The `kubycat.sync.excluding` option can be a list of regex file patterns to exclude from syncing. These are applied to the full path of the file being synced. These regexes are case-sensitive by default.

Example to disable syncing for IDE files:
```yaml
kubycat:
  sync:
    - name:
      ...
      from:
        - src
      excluding:
        - .+\.sw[pxo]$
        - .+~$
```

### kubycat.sync.including
The `kubycat.sync.including` option can be a list of regex file patterns to include in syncing. These are applied to the full path of the file being synced. These regexes are case-sensitive by default.

Example to only sync PHP files:
```yaml
kubycat:
  sync:
    - name: php-only
      from:
      - src
      ...
      including:
        - .+\.php$
```

The logic for inclusion/exclusion works as follows:
1. By default, any files in the "from" option will be synced.
2. Any files matching the "excluding" option will be excluded from syncing.
3. Any files matching the "including" option will be included in syncing regardless of whether they would otherwise be excluded by step 2.

### kubycat.sync.to
The `kubycat.sync.to` option specifies the remote path to sync files to. This must be an absolute path.

The to path is assumed to be logically equivalent to the `base` directory. For example, if the `base` directory is `/home/johndoe/test/` and the `to` path is `/remote/server` then the file `/home/johndoe/test/src/index.php` will be synced to `/remote/server/src/index.php`.

This field is optional in which case only the local command will be executed upon file change and no syncing will take place.

This is a convenient way to run a custom file watcher without needing to sync files, and for reloading configs.

### kubycat.sync.pod
The `kubycat.sync.pod` option specifies the name of the pod to sync files into. This is useful for simple deployments where you know the name of the single pod where you want to sync files.

### kubycat.sync.pod-label
Alternatively, the `kubycat.sync.pod-label` option can be used to specify a label to use to find the pod to sync files into. This is useful for deployments where you have multiple pods whose names you don't know but you can identify them by a label.

`pod` and `pod-label` are mutually exclusive and only one can be specified.

One of the two options must be specified if the `to` option is set.

### kubycat.sync.shell
The `kubycat.sync.shell` option specifies the shell to use when executing commands in the pod. This is required for deleting files and folders within the Kubernetes pods because `kubectl` provides no `rm` equivalent to `cp`.

This option is required if the `to` option is set.

### kubycat.sync.post-sync-local
The `kubycat.sync.post-sync-local` option specifies a local command to run after syncing files to the Kubernetes pod. This is useful for running commands like `composer install` or `npm install` to install dependencies.

You can also specify the special `kubycat::exit` command to exit Kubycat after a sync is performed.

This might be useful if you only want to sync a one-off change to a pod and then exit. 

**_Easter egg_**

Because Kubycat can perform commands on file syncing and file syncing is performed on file changes, you can write a sync config that will cause Kubycat to reload if it sees that its own configuration YAML file has changed. If you are also running Kubycat as a service, this will cause Kubycat to restart itself and pick up any changes to the configuration file.

```yaml
- name: kubycat-config
  base: /etc/kubycat
  from:
    - config.yaml
  post-sync-local: kubycat::reload
```

### kubycat.sync.post-sync-remote
The `kubycat.sync.post-sync-remote` option specifies a remote command to run in each pod after files have been synced. This is useful for running commands like `composer install` or `npm install` to install dependencies.


With both `post-sync-local` and `post-sync-remote` you can use the `{synced_file}`placeholder to specify the path to the local or remote file that was synced. This is useful if you want to run a command on a specific file that was synced.

### kubycat.sync.notify
The `kubycat.sync.notify` option can be used to send desktop notifications when syncing actions or other commands fail. The values for this option can be `notify-send` for Linux or `display notification` for MAC. On MAC, you may need to enable notifications for the terminal app.

This option is somewhat experimental and may not work on all systems.

### kubycat.sync.on-sync-error
The `kubycat.sync.on-sync-error` option specifies what to do when a sync fails. The options are `exit`, `reload`, and `ignore`. The default is `exit`.

1. Exit: Kubycat command line or service will stop and not restart.
2. Reload: Kubycat service will restart, command line will still exit.
3. Ignore: Kubycat will continue to run as if nothing happened.

### kubycat.sync.on-post-sync-error
The `kubycat.sync.on-post-sync-error` option specifies what to do when a post-sync command fails. The options are `exit`, `reload`, and `ignore`. The default is `exit`.

This works the same as the above option except that it applies to the local and remote post-syncing actions that Kubycat can be configured to perform when a sync is completed successfully.


## Usage
While Kubycat can be run as a service, you can also run it manually via the command line via `kubycat [subcommand] [options]`.

The only option at this time is the `--config` option which allows you to specify the location of the YAML configuration file, which defaults to `/etc/kubycat/config.yaml`.

### Syncing

Kubycat syncing is invoked via the `kubycat watch` subcommand.
```bash
$ ./kubycat watch
```

While running, Kubycat will watch the configured files for changes and sync them into the Kubernetes cluster.

Kubycat will display a list of commands that it is running as the files are synced.

In service mode, you can get the tail of the log file by running:
```bash
$ sudo systemctl --user status kubycat
```

### Manual Syncing
You can manually sync a file/folder by running:
```bash
$ ./kubycat sync <absolute_path>
```

This will find the sync configuration for the specified file/folder and sync it into the Kubernetes cluster.

This only works while the `kubycat watch` command is running.

### Version
You can view the current Kubycat version by running:
```bash
$ ./kubycat version
```

### Help
You can view the Kubycat help by running:
```bash
$ ./kubycat help
```

## About
I wrote Kubycat because I couldn't get `ksync` to work on my machine and I wanted a simple way to sync files into my minikube Kubernetes cluster for local development. I played around with other approaches such as `Skaffold`, but I found that they were too complex for my needs.

The problem at hand didn't seem too difficult, so I decided to write my own solution. It's far from polished, but it works for me quite nicely, and maybe that means others will find it helpful as well.

I'm currently using Kubycat for local development of [Dreamcloud](https://dreamcloud.app)--an online social network and dream journal to help people better understand their dreams and find likeminded individuals.

## Contributing
This is only the second release of Kubycat, so I'm aware that there are a lot of features that would be useful (file patterns, exclusions, etc.)
I'm also guessing that there will be a handful of bugs that I haven't found yet as my use cases are pretty limited. 
I'd be more than happy to accept pull requests for any of these features or bug fixes.

## License
MIT

<a href="https://www.buymeacoffee.com/sheldonjuncker" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" width=150 height=40></a>


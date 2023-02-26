[View Kubycat on GitHub](https://github.com/sheldonjuncker/kubycat)

<img src="https://www.kubycat.info/kubycat.jpg" alt="" width="75" style="float: right">

# kubycat 
A small perl script for syncing files into a Kubernetes cluster.

```perl
my $name = kubycat
my $version = 0.0.1
my $author = Sheldon Juncker <sheldon@dreamcloud.app>
my $github = https://github.com/sheldonjuncker/kubycat
my $license = MIT
```

## Installation
Kubycat requires fswatch and Perl 5.10 or higher to be installed on the system.
Most Linux distributions come with Perl pre-installed, but if you are on Windows you will need to install it.
You can view instructions for doing so here: https://learn.perl.org/installing/windows.html

### Step 0
_Install fswatch._
```bash
# Mac/Linux
$ brew install fswatch 

 # Linux
$ apt-get install fswatch

# Windows
$ explorer "https://github.com/emcrisostomo/fswatch/blob/master/README.windows"
```

### Step 1
_Clone the repository._
```bash
$ git clone https://github.com/sheldonjuncker/kubycat.git
```

### Step 2
_Install the CPAN modules._

Kubycat requires the following Perl modules:
- YAML::XS
- IO::Socket
- Digest::MD5
- File::Slurp
- Switch

You can automatically install these modules by running the install script:
```bash
$ cd kubycat
$ ./install
```

## Configuration
Kubycat is configured via a `config.yaml` file in the root directory of the project. An example file is provided in `config.example.yaml`.
```yaml
kubycat:
  # The Kubernetes config file to use
  config: /home/johndoe/.kube/config
  # The Kubernetes context to use
  context: minikube
  # The Kubernetes namespace to use
  # This can be specified or overridden for each individual sync
  namespace: default
  # The port to use for the kubycat file syncing server
  port: 1273
  # Individual sync configs
  sync:
      # The name of the sync
    - name: test
      # The base directory to sync from  
      base: /home/johndoe/test/
      # The Kubernetes namespace to use
      # leave blank to use the global namespace
      namespace: other
      # The file paths to sync
      # Note that all syncing is done recursively
      from:
        - src
        - config
        - index.php
      # The remote directory to sync into 
      to: /remote/server
      # The Kubernetes pod to sync into
      pod: pod-name
      # The Kubernetes pod label to use for finding the pod(s) to sync into
      # This can be used instead of specifying a single pod
      pod-label: key=value
      # The shell command to run in the container for deleting files
      shell: /bin/sh
```

You can copy this file to `config.yaml` and edit to suit your needs.
```bash
$ mv config.example.yaml config.yaml
```

## Usage
Kubycat is a simple command-line Perl script which can be invoked via the `./kubycat` command which conveniently works in either Linux or Windows because Linux is smart and uses the `kubycat` file and Windows is silly and uses the `kubycat.bat` file.

Note: I actually have no idea if this works on Windows, but it should.

### Syncing

Kubycat syncing is invoked via the `kubycat watch` command.
```bash
$ ./kubycat watch
```

While running, Kubycat will watch the configured files for changes and sync them into the Kubernetes cluster.

Kubycat will display a list of commands that it is running as the files are synced.

### Manual Syncing
You can manually sync a file/folder by running:
```bash
$ ./kubycat sync <absolute_path>
```

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

## Contributing
This is the first version of Kubycat, so I'm aware that there are a lot of features that would be useful (file patterns, exclusions, etc.)
I'm also guessing that there will be a handful of bugs that I haven't found yet as my use cases are pretty limited. 
I'd be more than happy to accept pull requests for any of these features or bug fixes.

## License
MIT



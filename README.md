# kubycat
A small perl package for syncing files into a Kubernetes cluster.

## Installation
Kubycat requires Perl 5.10 or higher to be installed on the system.

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







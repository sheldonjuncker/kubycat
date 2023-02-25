# kubycat
A small perl package for syncing files into a Kubernetes cluster.

## Installation
Kubycat requires Perl 5.10 or higher to be installed on the system.

It also requires the following Perl modules:
1. YAML::XS
2. IO::Socket
3. Digest::MD5
4. File::Slurp
5. Switch

You can automatically install these modules by running the install script:
```
$ ./install
```

## Configuration
Kubycat is configured via a `config.yaml` file in the root directory of the project. An example file is provided in the `config.yaml.example`.
```yaml
kubycat:
  # The Kubernetes config file to use
  config:
  # The Kubernetes context to use
  context:
  # The Kubernetes namespace to use
  # This can be specified or overridden for each individual sync
  namespace: elsewhere
  # The port to use for the kubycat file syncing server
  port: 1273
  # Individual sync configs
  sync:
      # The name of the sync (for display purposes)
    - name: 
      # The base directory to sync from  
      base: /home/sheldon/elsewhere/backend/api
      # The Kubernetes namespace to use
      # leave blank to use the global namespace
      namespace:
      # The file paths to sync
      # Note that all syncing is done recursively
      from:
        - path1
        - path2
        - index.php
      # The remote directory to sync into 
      to: /srv/api
      # The Kubernetes pod to sync into
      pod: elsewhere-php-85769c9bcf-2hsks
      # The Kubernetes pod label to use for finding the pod(s) to sync into
      # This can be used instead of specifying a single pod
      pod-label: key=value
      # The shell command to run in the container for deleting files
      shell: /bin/sh
```

## Usage
Kubycat is a simple command-line Perl script which can be invoked via the `./kubycat` command which conveniently works in either Linux or Windows because Linux is smart and uses the `kubycat` file and Windows is silly and uses the `kubycat.bat` file.

I actually have no idea if this works on Windows, but it should.

### Syncing

Kubycat syncing is invoked via the `kubycat watch` command.
```
$ ./kubycat watch
```

While running, Kubycat will watch the configured files for changes and sync them into the Kubernetes cluster.

Kubycat will display a list of commands that it is running as the files are synced.

### Manual Syncing
You can manually sync a file/folder by running:
```
$ ./kubycat sync <absolute_path>
```

### Version
You can view the current Kubycat version by running:
```
$ ./kubycat version
```

### Help
You can view the Kubycat help by running:
```
$ ./kubycat help
```







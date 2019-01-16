**!! NOTE !!** This tool is no longer maintained!

# puppet_docker_tools

Utilities for building and publishing the docker images at hub.docker.com/u/puppet

## Usage

### Getting Started

`puppet_docker_tools` is packaged as a gem, so to get started either `gem install puppet_docker_tools` or add `gem 'puppet_docker_tools'` to your Gemfile.

You also need to have docker installed and running. See [these docs](https://docs.docker.com/get-started/) for more information on getting docker set up.

```
$ puppet-docker help
Utilities for building and releasing Puppet docker images.

Usage:
  puppet-docker build [DIRECTORY] [--dockerfile=<dockerfile>] [--repository=<repo>] [--namespace=<namespace>] [--no-cache] [--version=<version>] [--build-arg=<buildarg> ...] [--no-latest]
  puppet-docker lint [DIRECTORY] [--dockerfile=<dockerfile>]
  puppet-docker local-lint [DIRECTORY] [--dockerfile=<dockerfile>]
  puppet-docker pull [IMAGE] [--repository=<repo>]
  puppet-docker push [DIRECTORY] [--dockerfile=<dockerfile>] [--repository=<repo>] [--namespace=<namespace>] [--version=<version>] [--no-latest]
  puppet-docker rev-labels [DIRECTORY] [--dockerfile=<dockerfile>] [--namespace=<namespace>]
  puppet-docker spec [DIRECTORY] [--image=<image>]
  puppet-docker test [DIRECTORY] [--dockerfile=<dockerfile>]
  puppet-docker version [DIRECTORY] [--dockerfile=<dockerfile>] [--namespace=<namespace>]
  puppet-docker update-base-images [TAG]...
  puppet-docker help

Arguments:
  DIRECTORY  Directory containing the Dockerfile for the image you're operating on. Defaults to $PWD
  IMAGE      The docker image to operate on, including namespace. Defaults to '<repo>/puppet_docker_tools'
  TAG        Pull latest versions of images at TAG. Defaults to ['ubuntu:16.04', 'centos:7', 'alpine:3.4', 'debian:9', 'postgres:9.6.8']

Options:
  --repository=<repo>        Docker repository containing the image [default: puppet]
  --no-cache                 Disable use of layer cache when building this image. Defaults to using the cache.
  --namespace=<namespace>    Namespace for labels on the container [default: org.label-schema]
  --dockerfile=<dockerfile>  File name for your dockerfile [default: Dockerfile]
  --version=<version>        Version to build. This field will be used to determine the label and will be passed as the version build arg.
                             **NOTE** `--build-arg version='<version>'` overrides `--version <version>`
  --image=<image>            Docker image to use for spec testing
  --build-arg=<buildarg>     Build arg to pass to container build, can be passed multiple times.
  --no-latest                Do not include the 'latest' tag when building and shipping images. By default, the 'latest' tag is built and shipped with the versioned tag.
```

### `puppet-docker build`

Build a docker image based on the dockerfile in DIRECTORY.

### `puppet-docker lint`

Run [hadolint](https://github.com/hadolint/hadolint) on the dockerfile in DIRECTORY. The lint task runs on the `hadolint/hadolint` container with the following rule exclusions:
* [DL3008](https://github.com/hadolint/hadolint/wiki/DL3008) - Pin versions in apt get install
* [DL3018](https://github.com/hadolint/hadolint/wiki/DL3018) - Pin versions in apk install
* [DL4000](https://github.com/hadolint/hadolint/wiki/DL4000) - MAINTAINER is deprecated
* [DL4001](https://github.com/hadolint/hadolint/wiki/DL4001) - Don't use both wget and curl

### `puppet-docker local-lint`

Run [hadolint](https://github.com/hadolint/hadolint) on the dockerfile in DIRECTORY. The lint task runs using a locally installed `hadolint` executable with the same rule exclusions as `puppet-docker lint`.

### `puppet-docker pull`

Pull the specified image, i.e. 'puppet/puppetserver'. *NOTE*: If you don't include the tag you want to pull, `puppet-docker pull` will pull all tags for that image.

### `puppet-docker push`

Push images built from the dockerfile in DIRECTORY to <repo>. This task will fail if you do not have a version specified in your dockerfile. It will push both a versioned and a 'latest' tagged image.

### `puppet-docker rev-labels`

Update `vcs-ref` and `build-date` labels in your dockerfile to current git sha and current UTC time.

### `puppet-docker spec`

Run the rspec tests under DIRECTORY/spec. Will run tests on files matching `*_spec.rb`.

### `puppet-docker test`

Shortcut to run both the `lint` and `spec` tasks.

### `puppet-docker version`

Output the `version` label for the dockerfile contained in DIRECTORY.

### `puppet-docker update-base-images`

Update the base images. Any number of tags to update can be passed, or by default it will pull the latest version of: ['ubuntu:16.04', 'centos:7', 'alpine:3.4', 'debian:9', 'postgres:9.6.8']

## Items available to Dockerfiles

There are some common variables passed to builds that you can take advantage of in your Dockerfiles.

### `ARG`s

* `vcs_ref`: set to `git rev-parse HEAD`
* `build_date`: set to ruby's `Time.now.utc.iso8601`

## Issues

File issues in the [Community Package Repository (CPR) project](https://tickets.puppet.com/browse/CPR) with the 'Container' component.

## License

See [LICENSE](LICENSE) file.

## Maintainers

This project is maintained by the release engineering team <release@puppet.com> at Puppet, Inc.

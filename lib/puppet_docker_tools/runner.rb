require 'date'
require 'json'
require 'rspec/core'
require 'time'
require 'puppet_docker_tools/utilities'
require 'puppet_docker_tools/spec_helper'

class PuppetDockerTools
  class Runner
    attr_accessor :directory, :repository, :namespace, :dockerfile

    def initialize(directory: , repository: , namespace: , dockerfile: )
      @directory = directory
      @repository = repository
      @namespace = namespace
      @dockerfile = dockerfile

      file = File.join(directory, dockerfile)
      fail "File #{file} doesn't exist!" unless File.exist? file
    end

    # Build a docker image from a directory
    #
    # @param no_cache Whether or not to use existing layer caches when building
    #        this image. Defaults to using the cache (no_cache = false).
    # @param version Set the version for the container explicitly. Will get
    #        passed as the 'version' buildarg.
    # @param build_args Pass arbitrary buildargs to the container build.
    #        Expected to be an array of strings, each string formatted like
    #        'arg=value'.
    # @param latest Whether or not to build the latest tag along with the
    #        versioned image build.
    def build(no_cache: false, version: nil, build_args: [], latest: true, stream_output: true)
      image_name = File.basename(directory)
      build_args_hash = {
        'vcs_ref' => PuppetDockerTools::Utilities.current_git_sha(directory),
        'build_date' => Time.now.utc.iso8601
      }

      # if version is passed in, add that into the build_args hash
      # **NOTE** if both `version` and `build_args` includes `version=something`
      #          the value in `build_args` takes precedence
      build_args_hash['version'] = version unless version.nil?

      # Convert the build_args array to a hash, and merge it with the values
      # that have already been set
      if Array(build_args).any?
        build_args_hash.merge!(PuppetDockerTools::Utilities.parse_build_args(Array(build_args)))
      end

      build_args_hash = PuppetDockerTools::Utilities.filter_build_args(build_args: build_args_hash, dockerfile: File.join(directory, dockerfile))

      # This variable is meant to be used for building the non-latest tagged build
      # If the version was set via `version` or `build_args`, use that. If not,
      # use `get_value_from_env` to parse that value from the dockerfile.
      #
      # If version hasn't been passed in via `version` or `build_args` there's
      # no need to add the version from `get_value_from_env` to the
      # build_args_hash, dockerfiles should not be using both hardcoded versions
      # and versions passed in to the dockerfile with an `ARG`
      version = build_args_hash['version'] || PuppetDockerTools::Utilities.get_value_from_env('version', namespace: namespace, directory: directory, dockerfile: dockerfile)

      path = File.join(repository, image_name)

      build_options = []
      if no_cache
        puts "Ignoring cache for #{path}"
        build_options << '--no-cache'
      end

      if dockerfile != "Dockerfile"
        build_options << ['--file', File.join(directory, dockerfile)]
      end

      tags = []
      if latest
        tags << ['--tag', "#{path}:latest"]
      end

      if version
        tags << ['--tag', "#{path}:#{version}"]
      end

      if tags.empty?
        return nil
      end


      build_args = []
      build_args_hash.map{ |k,v| "#{k}=#{v}" }.each do |val|
        build_args << ['--build-arg', val]
      end

      build_command = ['docker', 'build', build_args, build_options, tags, directory].flatten

      Open3.popen2e(*build_command) do |stdin, output_stream, wait_thread|
        output=''
        output_stream.each_line do |line|
          stream_output ? (puts line) : (output += line)
        end
        exit_status = wait_thread.value.exitstatus
        puts output unless stream_output
        fail unless exit_status == 0
      end
    end

    # Run hadolint on the Dockerfile in the specified directory. This will run
    # hadolint inside of a container. To run a locally-installed hadolint binary
    # see local_lint.
    #
    def lint
      hadolint_container = 'hadolint/hadolint'

      # make sure we have the container locally
      PuppetDockerTools::Utilities.pull("#{hadolint_container}:latest")
      docker_run = ['docker', 'run', '--rm', '-v', "#{File.join(Dir.pwd, directory, dockerfile)}:/Dockerfile:ro", '-i', 'hadolint/hadolint', PuppetDockerTools::Utilities.get_hadolint_command('Dockerfile')].flatten
      output, status = Open3.capture2e(*docker_run)
      fail output unless status == 0
    end

    # Run hadolint Dockerfile linting using a local hadolint executable. Executable
    # found based on your path.
    def local_lint
      output, status = Open3.capture2e(*PuppetDockerTools::Utilities.get_hadolint_command(File.join(directory,dockerfile)))
      fail output unless status == 0
    end

    # Push an image to $repository
    #
    # @param latest Whether or not to push the latest tag along with the
    #        versioned image build.
    def push(latest: true, version: nil)
      image_name = File.basename(directory)
      path = File.join(repository, image_name)

      # only check for version from the label if we didn't pass it in
      if version.nil?
        version = PuppetDockerTools::Utilities.get_value_from_label(path, value: 'version', namespace: namespace)
      end

      # We always want to push a versioned container
      unless version
        fail "No version specified in #{dockerfile} for #{path}"
      end

      puts "Pushing #{path}:#{version}"
      exitstatus, _ = PuppetDockerTools::Utilities.push_to_docker_repo("#{path}:#{version}")
      unless exitstatus == 0
        fail "Pushing #{path}:#{version} failed!"
      end

      if latest
        puts "Pushing #{path}:latest"
        exitstatus, _ = PuppetDockerTools::Utilities.push_to_docker_repo("#{path}:latest")
        unless exitstatus == 0
          fail "Pushing #{path}:latest failed!"
        end
      end
    end

    # Update vcs-ref and build-date labels in the Dockerfile
    #
    def rev_labels
      file = File.join(directory, dockerfile)

      values_to_update = {
        "#{namespace}.vcs-ref" => PuppetDockerTools::Utilities.current_git_sha(directory),
        "#{namespace}.build-date" => Time.now.utc.iso8601
      }

      text = File.read(file)
      values_to_update.each do |key, value|
        original = text.clone
        text = text.gsub(/#{key}=\"[a-z0-9A-Z\-:]*\"/, "#{key}=\"#{value}\"")
        puts "Updating #{key} in #{file}" unless original == text
      end

      File.open(file, 'w') { |f| f.puts text }
    end

    # Run spec tests
    #
    def spec(image: nil)
      if image
        fail 'Oh no! You have PUPPET_TEST_DOCKER_IMAGE set! Please unset!' if ENV['PUPPET_TEST_DOCKER_IMAGE']
        ENV['PUPPET_TEST_DOCKER_IMAGE'] = image
      end

      tests = Dir.glob(File.join(directory,'spec','*_spec.rb'))
      test_files = tests.map { |test| File.basename(test, '.rb') }

      puts "Running RSpec tests from #{File.expand_path(File.join(directory,'spec'))} (#{test_files.join ","}), this may take some time"
      success = true
      tests.each do |test|
        Open3.popen2e('rspec', 'spec', test) do |stdin, output_stream, wait_thread|
          output_stream.each_line do |line|
            puts line
          end
          exit_status = wait_thread.value.exitstatus
          success = success && (exit_status == 0)
        end
      end

      if image
        ENV['PUPPET_TEST_DOCKER_IMAGE'] = nil
      end

      fail "Running RSpec tests for #{directory} failed!" unless success
    end

    # Get the version set in the Dockerfile in the specified directory
    #
    def version
      puts PuppetDockerTools::Utilities.get_value_from_env('version', namespace: namespace, directory: directory, dockerfile: dockerfile)
    end
  end
end

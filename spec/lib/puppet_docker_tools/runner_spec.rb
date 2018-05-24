require 'puppet_docker_tools'
require 'puppet_docker_tools/runner'
require 'docker'

describe PuppetDockerTools::Runner do
  def create_runner(directory:, repository:, namespace:, dockerfile:)
    allow(File).to receive(:exist?).with("#{directory}/#{dockerfile}").and_return(true)
    PuppetDockerTools::Runner.new(directory: directory, repository: repository, namespace: namespace, dockerfile: dockerfile)
  end

  let(:runner) { create_runner(directory: '/tmp/test-image', repository: 'test', namespace: 'org.label-schema', dockerfile: 'Dockerfile') }

  describe '#initialize' do
    it "should fail if the dockerfile doesn't exist" do
      allow(File).to receive(:exist?).with('/tmp/test-image/Dockerfile').and_return(false)
      expect { PuppetDockerTools::Runner.new(directory: '/tmp/test-image', repository: 'test', namespace: 'org.label-schema', dockerfile: 'Dockerfile') }.to raise_error(RuntimeError, /doesn't exist/)
    end
  end

  describe '#build' do
    let(:image) { double(Docker::Image) }

    it 'builds a latest and version tag if version is found' do
      expect(PuppetDockerTools::Utilities).to receive(:get_value_from_env).with('version', namespace: runner.namespace, directory: runner.directory, dockerfile: runner.dockerfile).and_return('1.2.3')
      expect(Docker::Image).to receive(:build_from_dir).with(runner.directory, { 't' => 'test/test-image:1.2.3', 'dockerfile' => runner.dockerfile }).and_return(image)
      expect(Docker::Image).to receive(:build_from_dir).with(runner.directory, { 't' => 'test/test-image:latest', 'dockerfile' => runner.dockerfile }).and_return(image)
      runner.build
    end

    it 'builds just a latest tag if no version is found' do
      expect(PuppetDockerTools::Utilities).to receive(:get_value_from_env).with('version', namespace: runner.namespace, directory: runner.directory, dockerfile: runner.dockerfile).and_return(nil)
      expect(Docker::Image).to receive(:build_from_dir).with(runner.directory, { 't' => 'test/test-image:latest', 'dockerfile' => runner.dockerfile }).and_return(image)
      runner.build
    end

    it 'ignores the cache when that parameter is set' do
      expect(PuppetDockerTools::Utilities).to receive(:get_value_from_env).with('version', namespace: runner.namespace, directory: runner.directory, dockerfile: runner.dockerfile).and_return(nil)
      expect(Docker::Image).to receive(:build_from_dir).with(runner.directory, { 't' => 'test/test-image:latest', 'nocache' => true, 'dockerfile' => runner.dockerfile }).and_return(image)
      runner.build(no_cache: true)
    end

    it 'uses a custom dockerfile if passed' do
      allow(File).to receive(:exist?).with('/tmp/test-image/Dockerfile.test').and_return(true)
      expect(PuppetDockerTools::Utilities).to receive(:get_value_from_env).with('version', namespace: 'org.label-schema', directory: '/tmp/test-image', dockerfile: 'Dockerfile.test').and_return(nil)
      expect(Docker::Image).to receive(:build_from_dir).with('/tmp/test-image', { 't' => 'test/test-image:latest', 'dockerfile' => 'Dockerfile.test' }).and_return(image)
      local_runner = create_runner(directory: '/tmp/test-image', repository: 'test', namespace: 'org.label-schema', dockerfile: 'Dockerfile.test')
      local_runner.build
    end
  end

  describe '#lint' do
    let(:passing_exit) {
      {
        'State' => {
          'ExitCode' => 0
        }
      }
    }
    let(:failing_exit) {
      {
        'State' => {
          'ExitCode' => 1
        }
      }
    }

    let(:container) { double(Docker::Container).as_null_object }

    before do
      allow(PuppetDockerTools::Utilities).to receive(:pull).and_return(double(Docker::Image))
      allow(Docker::Container).to receive(:create).and_return(container)
      allow(container).to receive(:tap).and_return(container)
      allow(container).to receive(:attach)
      allow(container).to receive(:wait)
      allow(container).to receive(:logs).and_return('container logs')
    end

    it "should lint the container" do
      allow(container).to receive(:json).and_return(passing_exit)
      runner.lint
    end

    it "should exit with exit status if something went wrong" do
      allow(container).to receive(:json).and_return(failing_exit)
      expect { runner.lint }.to raise_error(RuntimeError, /container logs/)
    end
  end

  describe '#push' do
    it 'should fail if no version is set' do
      expect(PuppetDockerTools::Utilities).to receive(:get_value_from_label).and_return(nil)
      expect { runner.push }.to raise_error(RuntimeError, /no version/i)
    end

    it 'should raise an error if something bad happens pushing the versioned tag' do
      expect(PuppetDockerTools::Utilities).to receive(:get_value_from_label).with('test/test-image', value: 'version', namespace: runner.namespace).and_return('1.2.3')
      expect(PuppetDockerTools::Utilities).to receive(:push_to_dockerhub).with('test/test-image:1.2.3').and_return([1, nil])
      expect { runner.push }.to raise_error(RuntimeError, /1.2.3 to dockerhub/i)
    end

    it 'should raise an error if something bad happens pushing the latest tag' do
      expect(PuppetDockerTools::Utilities).to receive(:get_value_from_label).with('test/test-image', value: 'version', namespace: runner.namespace).and_return('1.2.3')
      expect(PuppetDockerTools::Utilities).to receive(:push_to_dockerhub).with('test/test-image:1.2.3').and_return([0, nil])
      expect(PuppetDockerTools::Utilities).to receive(:push_to_dockerhub).with('test/test-image:latest').and_return([1, nil])
      expect { runner.push }.to raise_error(RuntimeError, /latest to dockerhub/i)
    end

    it 'should push the versioned and latest tags if nothing goes wrong' do
      expect(PuppetDockerTools::Utilities).to receive(:get_value_from_label).with('test/test-image', value: 'version', namespace: runner.namespace).and_return('1.2.3')
      expect(PuppetDockerTools::Utilities).to receive(:push_to_dockerhub).with('test/test-image:1.2.3').and_return([0, nil])
      expect(PuppetDockerTools::Utilities).to receive(:push_to_dockerhub).with('test/test-image:latest').and_return([0, nil])
      runner.push
    end
  end

  describe '#rev_labels' do
    let(:original_dockerfile) { <<-HERE
FROM ubuntu:16.04

ENV PUPPET_SERVER_VERSION="5.3.1" DUMB_INIT_VERSION="1.2.1" UBUNTU_CODENAME="xenial" PUPPETSERVER_JAVA_ARGS="-Xms256m -Xmx256m" PATH=/opt/puppetlabs/server/bin:/opt/puppetlabs/puppet/bin:/opt/puppetlabs/bin:$PATH PUPPET_HEALTHCHECK_ENVIRONMENT="production"

LABEL maintainer="Puppet Release Team <release@puppet.com>" \\
      org.label-schema.vcs-ref="b75674e1fbf52f7821f7900ab22a19f1a10cafdb" \\
      org.label-schema.build-date="2018-05-09T20:11:01Z"
HERE
    }

    let(:updated_dockerfile) { <<-HERE
FROM ubuntu:16.04

ENV PUPPET_SERVER_VERSION="5.3.1" DUMB_INIT_VERSION="1.2.1" UBUNTU_CODENAME="xenial" PUPPETSERVER_JAVA_ARGS="-Xms256m -Xmx256m" PATH=/opt/puppetlabs/server/bin:/opt/puppetlabs/puppet/bin:/opt/puppetlabs/bin:$PATH PUPPET_HEALTHCHECK_ENVIRONMENT="production"

LABEL maintainer="Puppet Release Team <release@puppet.com>" \\
      org.label-schema.vcs-ref="8d7b9277c02f5925f5901e5aeb4df9b8573ac70e" \\
      org.label-schema.build-date="2018-05-14T22:35:15Z"
HERE
    }

    it "should update vcs-ref and build-date" do
      test_dir = Dir.mktmpdir('spec')
      File.open("#{test_dir}/Dockerfile", 'w') { |file|
        file.puts(original_dockerfile)
      }
      local_runner = create_runner(directory: test_dir, repository: 'test', namespace: 'org.label-schema', dockerfile: 'Dockerfile')
      expect(PuppetDockerTools::Utilities).to receive(:current_git_sha).with(test_dir).and_return('8d7b9277c02f5925f5901e5aeb4df9b8573ac70e')
      expect(Time).to receive(:now).and_return(Time.at(1526337315))
      local_runner.rev_labels
      expect(File.read("#{test_dir}/#{local_runner.dockerfile}")).to eq(updated_dockerfile)

      # cleanup cleanup
      FileUtils.rm("#{test_dir}/#{local_runner.dockerfile}")
      FileUtils.rmdir(test_dir)
    end
  end

  describe '#spec' do
    it "runs tests under the 'spec' directory" do
      tests=["/tmp/test-image/spec/test1_spec.rb", "/tmp/test-image/spec/test2_spec.rb"]
      expect(Dir).to receive(:glob).with("/tmp/test-image/spec/*_spec.rb").and_return(tests)
      expect(Open3).to receive(:popen2e).with('rspec spec /tmp/test-image/spec/test1_spec.rb')
      expect(Open3).to receive(:popen2e).with('rspec spec /tmp/test-image/spec/test2_spec.rb')
      runner.spec
    end
  end
end

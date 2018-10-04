require 'puppet_docker_tools'
require 'puppet_docker_tools/runner'
require 'tmpdir'

describe PuppetDockerTools::Runner do
  def create_runner(directory:, repository:, namespace:, dockerfile:)
    allow(File).to receive(:exist?).with("#{directory}/#{dockerfile}").and_return(true)
    allow(Dir).to receive(:chdir).with(directory).and_return('b0c5ead01b6cabdb3f01871bce699be165c3288f')
    allow(Time).to receive(:now).and_return(Time.at(1528478293))
    PuppetDockerTools::Runner.new(directory: directory, repository: repository, namespace: namespace, dockerfile: dockerfile)
  end

  let(:runner) { create_runner(directory: '/tmp/test-image', repository: 'test', namespace: 'org.label-schema', dockerfile: 'Dockerfile') }
  let(:buildargs) {{ 'vcs_ref' => 'b0c5ead01b6cabdb3f01871bce699be165c3288f', 'build_date' => '2018-06-08T17:18:13Z' }.to_json}
  let(:buildargs_with_version) {{ 'vcs_ref' => 'b0c5ead01b6cabdb3f01871bce699be165c3288f', 'build_date' => '2018-06-08T17:18:13Z', 'version' => '1.2.3' }.to_json}
  let(:extra_buildargs) {{ 'vcs_ref' => 'b0c5ead01b6cabdb3f01871bce699be165c3288f', 'build_date' => '2018-06-08T17:18:13Z', 'foo' => 'bar', 'baz' => 'test=with=equals' }.to_json}
  let(:read_dockerfile) {
    "FROM ubuntu:16.04\n\nARG vcs_ref\nARG build_date"
  }
  let(:read_dockerfile_with_version) {
    "FROM ubuntu:16.04\n\nARG version\nARG vcs_ref\nARG build_date"
  }
  let(:read_dockerfile_with_arbitrary_args) {
    "FROM ubuntu:16.04\n\nARG foo\nARG baz\nARG vcs_ref\nARG build_date"
  }

  describe '#initialize' do
    it "should fail if the dockerfile doesn't exist" do
      allow(File).to receive(:exist?).with('/tmp/test-image/Dockerfile').and_return(false)
      expect { PuppetDockerTools::Runner.new(directory: '/tmp/test-image', repository: 'test', namespace: 'org.label-schema', dockerfile: 'Dockerfile') }.to raise_error(RuntimeError, /doesn't exist/)
    end
  end

  describe '#build' do
    it 'builds a latest and version tag if version is found' do
      expect(File).to receive(:read).with("#{runner.directory}/#{runner.dockerfile}").and_return(read_dockerfile)
      expect(PuppetDockerTools::Utilities).to receive(:get_value_from_env).with('version', namespace: runner.namespace, directory: runner.directory, dockerfile: runner.dockerfile).and_return('1.2.3')
      expect(Open3).to receive(:popen2e).with('docker', 'build', '--build-arg', 'vcs_ref=b0c5ead01b6cabdb3f01871bce699be165c3288f', '--build-arg', 'build_date=2018-06-08T17:18:13Z', '--tag', 'test/test-image:latest', '--tag', 'test/test-image:1.2.3', runner.directory)
      runner.build
    end

    it 'builds just a latest tag if no version is found' do
      expect(File).to receive(:read).with("#{runner.directory}/#{runner.dockerfile}").and_return(read_dockerfile)
      expect(PuppetDockerTools::Utilities).to receive(:get_value_from_env).with('version', namespace: runner.namespace, directory: runner.directory, dockerfile: runner.dockerfile).and_return(nil)
      expect(Open3).to receive(:popen2e).with('docker', 'build', '--build-arg', 'vcs_ref=b0c5ead01b6cabdb3f01871bce699be165c3288f', '--build-arg', 'build_date=2018-06-08T17:18:13Z', '--tag', 'test/test-image:latest', runner.directory)
      runner.build
    end

    it 'does not build a latest tag if latest is set to false' do
      expect(File).to receive(:read).with("#{runner.directory}/#{runner.dockerfile}").and_return(read_dockerfile)
      expect(PuppetDockerTools::Utilities).to receive(:get_value_from_env).with('version', namespace: runner.namespace, directory: runner.directory, dockerfile: runner.dockerfile).and_return('1.2.3')
      expect(Open3).to receive(:popen2e).with('docker', 'build', '--build-arg', 'vcs_ref=b0c5ead01b6cabdb3f01871bce699be165c3288f', '--build-arg', 'build_date=2018-06-08T17:18:13Z', '--tag', 'test/test-image:1.2.3', runner.directory)
      runner.build(latest: false)
    end

    it 'ignores the cache when that parameter is set' do
      expect(File).to receive(:read).with("#{runner.directory}/#{runner.dockerfile}").and_return(read_dockerfile)
      expect(PuppetDockerTools::Utilities).to receive(:get_value_from_env).with('version', namespace: runner.namespace, directory: runner.directory, dockerfile: runner.dockerfile).and_return(nil)
      expect(Open3).to receive(:popen2e).with('docker', 'build', '--build-arg', 'vcs_ref=b0c5ead01b6cabdb3f01871bce699be165c3288f', '--build-arg', 'build_date=2018-06-08T17:18:13Z', '--no-cache', '--tag', 'test/test-image:latest', runner.directory)
      runner.build(no_cache: true)
    end

    it 'passes the version when that parameter is set' do
      expect(File).to receive(:read).with("#{runner.directory}/#{runner.dockerfile}").and_return(read_dockerfile_with_version)
      expect(Open3).to receive(:popen2e).with('docker', 'build', '--build-arg', 'vcs_ref=b0c5ead01b6cabdb3f01871bce699be165c3288f', '--build-arg', 'build_date=2018-06-08T17:18:13Z', '--build-arg', 'version=1.2.3', '--tag', 'test/test-image:latest', '--tag', 'test/test-image:1.2.3', runner.directory)
      runner.build(version: '1.2.3')
    end

    it 'passes arbitrary build args' do
      expect(File).to receive(:read).with("#{runner.directory}/#{runner.dockerfile}").and_return(read_dockerfile_with_arbitrary_args)
      expect(PuppetDockerTools::Utilities).to receive(:get_value_from_env).with('version', namespace: runner.namespace, directory: runner.directory, dockerfile: runner.dockerfile).and_return(nil)
      expect(Open3).to receive(:popen2e).with('docker', 'build', '--build-arg', 'vcs_ref=b0c5ead01b6cabdb3f01871bce699be165c3288f', '--build-arg', 'build_date=2018-06-08T17:18:13Z', '--build-arg', 'foo=bar', '--build-arg', 'baz=test=with=equals', '--tag', 'test/test-image:latest', runner.directory)
      runner.build(build_args: ['foo=bar', 'baz=test=with=equals'])
    end

    it 'prioritizes version as a build arg over regular version' do
      expect(File).to receive(:read).with("#{runner.directory}/#{runner.dockerfile}").and_return(read_dockerfile_with_version)
      expect(Open3).to receive(:popen2e).with('docker', 'build', '--build-arg', 'vcs_ref=b0c5ead01b6cabdb3f01871bce699be165c3288f', '--build-arg', 'build_date=2018-06-08T17:18:13Z', '--build-arg', 'version=1.2.3', '--tag', 'test/test-image:latest', '--tag', 'test/test-image:1.2.3', runner.directory)
      runner.build(version: '1.2.4', build_args: ['version=1.2.3'])
    end

    it 'uses a custom dockerfile if passed' do
      allow(File).to receive(:exist?).with('/tmp/test-image/Dockerfile.test').and_return(true)
      expect(File).to receive(:read).with('/tmp/test-image/Dockerfile.test').and_return(read_dockerfile)
      expect(PuppetDockerTools::Utilities).to receive(:get_value_from_env).with('version', namespace: 'org.label-schema', directory: '/tmp/test-image', dockerfile: 'Dockerfile.test').and_return(nil)
      expect(Open3).to receive(:popen2e).with('docker', 'build', '--build-arg', 'vcs_ref=b0c5ead01b6cabdb3f01871bce699be165c3288f', '--build-arg', 'build_date=2018-06-08T17:18:13Z', '--no-cache', '--file', '/tmp/test-image/Dockerfile.test', '--tag', 'test/test-image:latest', runner.directory)
      local_runner = create_runner(directory: '/tmp/test-image', repository: 'test', namespace: 'org.label-schema', dockerfile: 'Dockerfile.test')
      local_runner.build(no_cache: true)
    end
  end

  describe '#lint' do
    before do
      allow(PuppetDockerTools::Utilities).to receive(:pull)
    end

    it "should lint the container" do
      allow(Open3).to receive(:capture2e).and_return(['', 0])
      runner.lint
    end

    it "should exit with exit status if something went wrong" do
      allow(Open3).to receive(:capture2e).and_return(['container logs', 1])
      expect { runner.lint }.to raise_error(RuntimeError, /container logs/)
    end
  end

  describe '#local_lint' do
    it "should fail with logs if linting fails" do
      allow(Open3).to receive(:capture2e).with(*PuppetDockerTools::Utilities.get_hadolint_command('/tmp/test-image/Dockerfile')).and_return('container logs', 1)
      expect { runner.local_lint }.to raise_error(RuntimeError, /container logs/)
    end
  end

  describe '#push' do
    it 'should fail if no version is set' do
      expect(PuppetDockerTools::Utilities).to receive(:get_value_from_label).and_return(nil)
      expect { runner.push }.to raise_error(RuntimeError, /no version/i)
    end

    it 'should raise an error if something bad happens pushing the versioned tag' do
      expect(PuppetDockerTools::Utilities).to receive(:get_value_from_label).with('test/test-image', value: 'version', namespace: runner.namespace).and_return('1.2.3')
      expect(PuppetDockerTools::Utilities).to receive(:push_to_docker_repo).with('test/test-image:1.2.3').and_return([1, nil])
      expect { runner.push }.to raise_error(RuntimeError, /1.2.3 failed/i)
    end

    it 'should raise an error if something bad happens pushing the latest tag' do
      expect(PuppetDockerTools::Utilities).to receive(:get_value_from_label).with('test/test-image', value: 'version', namespace: runner.namespace).and_return('1.2.3')
      expect(PuppetDockerTools::Utilities).to receive(:push_to_docker_repo).with('test/test-image:1.2.3').and_return([0, nil])
      expect(PuppetDockerTools::Utilities).to receive(:push_to_docker_repo).with('test/test-image:latest').and_return([1, nil])
      expect { runner.push }.to raise_error(RuntimeError, /latest failed/i)
    end

    it 'should push the versioned and latest tags if nothing goes wrong' do
      expect(PuppetDockerTools::Utilities).to receive(:get_value_from_label).with('test/test-image', value: 'version', namespace: runner.namespace).and_return('1.2.3')
      expect(PuppetDockerTools::Utilities).to receive(:push_to_docker_repo).with('test/test-image:1.2.3').and_return([0, nil])
      expect(PuppetDockerTools::Utilities).to receive(:push_to_docker_repo).with('test/test-image:latest').and_return([0, nil])
      runner.push
    end

    it 'should not push the latest tag if latest is set to false' do
      expect(PuppetDockerTools::Utilities).to receive(:get_value_from_label).with('test/test-image', value: 'version', namespace: runner.namespace).and_return('1.2.3')
      expect(PuppetDockerTools::Utilities).to receive(:push_to_docker_repo).with('test/test-image:1.2.3').and_return([0, nil])
      runner.push(latest: false)
    end

    it "shouldn't look for the version if it's passed" do
      expect(PuppetDockerTools::Utilities).not_to receive(:get_value_from_label)
      expect(PuppetDockerTools::Utilities).to receive(:push_to_docker_repo).with('test/test-image:4.5.6').and_return([0, nil])
      expect(PuppetDockerTools::Utilities).to receive(:push_to_docker_repo).with('test/test-image:latest').and_return([0, nil])
      runner.push(version: '4.5.6')
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
      expect(Open3).to receive(:popen2e).with('rspec', 'spec', '/tmp/test-image/spec/test1_spec.rb')
      expect(Open3).to receive(:popen2e).with('rspec', 'spec', '/tmp/test-image/spec/test2_spec.rb')
      runner.spec
    end
  end
end

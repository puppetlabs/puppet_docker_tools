require 'open3'

shared_context 'with a docker container' do
  def is_running?(container)
    is_running = false
    output, _ = Open3.capture2e('docker', 'inspect', '--format', "'{{ .Config.Healthcheck }}'", "#{container}")
    output.chomp!
    output.gsub!(/'/, '')

    # no configured healthcheck
    if output.chomp == "<nil>"
      command = ['docker', 'inspect', '-f', "'{{.State.Status}}'", "#{container}"]
    else
      command = ['docker', 'inspect', '-f', "'{{.State.Health.Status}}'", "#{container}"]
    end

    while ! is_running
      output, _ = Open3.capture2e(*command)
      output.chomp!
      output.gsub!(/'/, '')

      case output
      when 'healthy', 'running'
        return true
      when 'unhealthy', 'removing', 'paused', 'exited', 'dead'
        return false
      end

      puts "Container is not running yet, will try again in 5 seconds..."
      sleep(5)
    end
  end

  def docker_run_options
    return ''
  end

  before(:all) do
    @container = %x(docker run #{docker_run_options} --detach --rm -i #{@image}).chomp

    unless $? == 0
      fail "something went wrong with container startup!\n#{output}"
    end

    unless is_running?(@container)
      logs = %x(docker container logs #{@container})
      fail "something went wrong with container startup!\n#{logs}"
    end
  end

  after(:all) do
    %x(docker container kill #{@container})
  end
end

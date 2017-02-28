#!/usr/bin/env ruby

require 'httparty'
require 'socket'

# Loop and poll the metadata route for spot instance termination
# When we are terminated...
#     1) Use hacks to print a message to every buildkite output
#     2) send SIGQUIT to all buildkite-agent instances; this makes them fail their current jobs
#     3) use the buildkite API to trigger a retry of the job
#     4) Trigger an ACPI shutdown of the box.

instance_id = HTTParty.get('http://169.254.169.254/latest/meta-data/instance-id').body
hostname = Socket.gethostname

loop do
    r = HTTParty.get('http://169.254.169.254/latest/meta-data/spot/termination-time')
    if r.code == 404
        # Not terminated yet.
        sleep 5
        next
    end

    # OOOOEEEE NNOOOEEEZZZZ !!!!!! TERMINATE!

    # Find a list of the jobs this agent is running
    agents = JSON.parse(
        HTTParty.get(
            "https://api.buildkite.com/v2/organizations/stile-education/agents",
            query: {
                "hostname" => hostname,
                "access_token" => ENV['BUILDKITE_TOKEN'],
                "per_page" => "100",
            }
        ).body
    )
    job_links = agents.map { |agent|
        next nil unless agent.has_key?('job') && agent['job']
        agent['job']['build_url'].chomp('/') + "/jobs/#{agent['job']['id']}"
    }.compact

    # Find any bash process with buildkite-agent open
    Dir.glob('/proc/[0-9]*').select { |proc|
        # Any bash process....
        File.readlink(File.join(proc, 'exe')) == '/bin/bash' rescue false
    }.select { |proc|
        # ..with bootstrap.sh open...
        Dir.glob(File.join(proc, 'fd/*')).any? { |fd|
            File.readlink(fd) == '/etc/buildkite-agent/bootstrap.sh' rescue false
        }
    }.each do |proc|
        # ...log to its console
        File.open(File.join(proc, 'fd/1'), 'a') do |f|
            f.puts "WARNING WARNING: AUTOSCALING INSTANCE #{instance_id} IS TERMINATING DUE TO SPOT PRICE INCREASE"
            f.puts "CANCELLING THIS JOB AND REQUEING IT ELSEWHERE."
            f.puts "MORE CAPITAL LETTERS SO THAT THIS THING LOOKS OBVIOUS IN LOG OUTPUT"
            f.puts "THIS BETTER BE REALLY VISIBLE AS A BLOCK OF CAPS IN THE BUILDKITE PAGE"
        end
    end

    # Now send SIGQUIT to any buildkite-agents
    Dir.glob('/proc/[0-9]*').select { |proc|
        File.readlink(File.join(proc, 'exe')).start_with?('/usr/bin/buildkite-agent') rescue false
    }.each do |proc|
        pid = File.basename(proc).to_i
        puts "Sending SIGQUIT to #{pid}"
        Process.kill('QUIT', pid)
    end

    # Give everything a few seconds to do their thing - the effect of the SIGQUIT is not synchronous
    while Dir.glob('/proc/[0-9]*').any? { |proc| File.readlink(File.join(proc, 'exe')).start_with?('/usr/bin/buildkite-agent') rescue false }
        puts "Waiting for buildkite-agent processes to exit..."
        sleep 1
    end

    sleep 2 # Bonus sleeps


    # Now use the buildkite API to restart the jobs we just mutilated.
    job_links.each do |job_link|
        loop do
            r = HTTParty.put(
                job_link + '/retry',
                headers: {
                    "Authorization" => "Bearer #{ENV['BUILDKITE_TOKEN']}"
                }
            )
            if (r.code == 400 || r.code == 403)
                # Not marked failed yet - try agian
                sleep 0.5
            else
                break
            end
        end
    end

    # ACPI shutdown.
    puts "ACPI shutdown"
    exec '/sbin/halt'
end

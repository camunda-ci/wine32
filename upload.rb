require "colorize"
require "popen4"
require "fileutils"

pad_length = 65
$stdout.sync = true
global_status = 0

pulp_server= ENV['PULP_SERVER']
pulp_repo = ARGV[0]
pulp_user = ENV['PULP_USER']
pulp_password = ENV['PULP_PASSWORD']

pulp_conf = ''
pulp_conf << "[server]\n"
pulp_conf << "host = #{pulp_server}\n"
pulp_conf << "verify_ssl = false\n"

FileUtils.mkdir_p "#{ENV['HOME']}/.pulp"
File.write("#{ENV['HOME']}/.pulp/admin.conf", pulp_conf)

commands = {
  "Pulp login" => "pulp-admin login -u #{pulp_user} -p #{pulp_password}",
  "Pulp upload to repo #{pulp_repo.light_blue}" =>
  "pulp-admin rpm repo uploads rpm --repo-id #{pulp_repo} --skip-existing -d .",
  "Pulp publish" => "pulp-admin rpm repo publish run --repo-id #{pulp_repo} --force-full"}

commands.each do |key, value|
  command_desc = key
  command = value
  outputs = ''
  errors =  ''
  print "#{command_desc}...".ljust(pad_length, padstr='.')
  command_status = POpen4::popen4(command) do |stdout, stderr, stdin|
    stdout.each do |line|
      outputs << "#{line.strip}\n"
    end
    stderr.each do |line|
      errors << "#{line.strip}\n"
    end
  end
  if command_status.exitstatus == 0
    print "Success.\n".green
  else
    print "Failure:\n".red
    print "#{outputs.strip}\n".red 
    print "#{errors.strip}\n".red 
    global_status = command_status.exitstatus
  end
end
exit global_status

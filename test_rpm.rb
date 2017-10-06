require "bundler/setup"
require "yaml"
require "colorize"
require "rpm"
require "popen4"

$stdout.sync = true
global_status = 0

namespace=ENV['CI_PROJECT_NAMESPACE']
project=ENV['CI_PROJECT_NAME']

# Functions
# Function to convert (yaml) object to has with symbol keys
def symbolize(obj)
    return obj.inject({}){|memo,(k,v)| memo[k.to_sym] =  symbolize(v); memo} if obj.is_a? Hash
    return obj.inject([]){|memo,v    | memo           << symbolize(v); memo} if obj.is_a? Array
    return obj
end

# Function to get system ready to sign RPM files
def trust_gpg_key(public_key)
  file = File.open("/tmp/public", "w")
  file.write(public_key)
  file.close
  commands = {
  'Importing GPG public key........' => 'rpm --import /tmp/public' }
  commands.each do |key, value|
    command_desc = key
    command = value
    print "#{command_desc}"
    outputs = ''
    errors =  ''
    command_status = POpen4::popen4(command) do |stdout, stderr, stdin|
      stdout.each do |line|
        outputs << "#{line.strip}\n"
      end
      stderr.each do |line|
        errors << "#{line.strip}\n"
      end
    end
    if command_status.exitstatus == 0
      print "Success: Action completed.\n".green
    else
      print "Failure:\n".red
      print "#{outputs.strip}\n".red
      print "#{errors.strip}\n".red
      global_status = command_status.exitstatus
    end
  end
end

# Function to check if package is currently available using yum
def pkg_in_yum?(package)
  outputs = ''
  errors = ''
  command_status = POpen4::popen4("repoquery --whatprovides '#{package}' --qf '%{REPO}'")  do |stdout, stderr, stdin|
    stdout.each do |line|
      outputs << "#{line.strip}\n"
    end
    stderr.each do |line|
      errors << "#{line.strip}\n"
    end
  end
  if command_status.exitstatus == 0 && outputs.length > 0
    return outputs
  else
    return false
  end
end

yaml = YAML::load_file(File.join(__dir__, 'packages.yml'))
yaml = symbolize(yaml)
packages = yaml[:packages]

# Trust the GPG key
trust_gpg_key(ENV['GPG_PUBLIC_KEY'])


# RPM tests
print "*************\n".light_blue
print "* RPM tests *\n".light_blue
print "*************\n".light_blue
packages.each_value do |package|
  package_name = package[:name]
  file_name = ''
  file_error = ''
  print "RPM tests for #{package_name.light_blue}:"
  # Does the package exist in standard repos?
  repo = pkg_in_yum?("rubygem-#{package_name}")
  if repo && !package[:force_new_version]
    print "Skipped: Pkg exists in ".yellow
    print repo.light_blue
    print " repo.\n".yellow
  else
    print "\n"
    # File exists?
    print "  File exists?................"
    dir_result = Dir["rubygem-#{package_name}-[0-9]*.rpm"]
    if dir_result.empty?
      print "Failure: #{package_name} RPM does not exist.\n".red
      global_status += 1
    else
      file_name = dir_result[0]
      print "Success: '#{file_name}'\n".green

      # RPM testing
      pkg = XRPM::Package.open(file_name)

      # RPM has a name?
      print "  RPM has a name?............."
      begin
        pkg_name = pkg.name
      rescue StandardError => error
      end
      if pkg_name.nil?
        print "Failure: #{file_name} has no name. #{error.to_s.strip}\n".red
        global_status += 1
      else
        print "Success: '#{pkg_name}'.\n".green
      end

      # RPM has a version?
      print "  RPM has a version?.........."
      begin
        pkg_version = pkg.version.v
      rescue StandardError => error
      end
      if pkg_version.nil?
        print "Failure: #{file_name} has no version. #{error.to_s.strip}\n".red
        global_status += 1
      else
        print "Success: '#{pkg_version}'.\n".green
      end

      #RPM has an iteration?
      print "  RPM has an iteration?......."
      begin
        pkg_iteration = pkg.version.r
      rescue StandardError => error
      end
      if pkg_iteration.nil?
        print "Failure: #{file_name} has no iteration. #{error.to_s.strip}\n".red
        global_status += 1
      else
        print "Success: '#{pkg_iteration}'.\n".green
      end

      #RPM contains files?
      print "  RPM contains files?........."
      begin
        pkg_files = pkg.files
      rescue StandardError => error
      end
      if pkg_files.nil?
        print "Failure: #{file_name} has no file count. #{error.to_s.strip}\n".red
        global_status += 1
      else
        if pkg_files.count == 0
          print "Warning: #{file_name} has file count of 0.\n".yellow
        else
          print "Success: #{pkg_files.count} files counted.\n".green
        end
      end

      #RPM contains dependenices?
      print "  RPM contains dependencies?.."
      begin
        pkg_requires = pkg.requires
      rescue StandardError => error
      end
      if pkg_requires.nil?
        print "Failure: #{file_name} has no dependencies. #{error.to_s.strip}\n".red
        global_status += 1
      else
        dependencies = []
        pkg.requires.each do |dependency|
          dependencies << { :name => dependency.name, :version => dependency.version.v }
        end
        print  "Success:".green
        dependencies.each do | dependency |
          print "\n    "
          print "#{dependency[:name]}".ljust(50).light_blue
          unless dependency[:version] == ""
            print " >= "
            print "#{dependency[:version]}".light_blue
          end
        end
        print "\n"
      end
      
     #RPM provides?
      print "  RPM provides?..............."
      begin
        pkg_provides = pkg.provides
      rescue StandardError => error
      end
      if pkg_provides.nil?
        print "Failure: #{file_name} provides nothing. #{error.to_s.strip}\n".red
        global_status += 1
      else
        provides = []
        pkg.provides.each do |provide|
          #provides << provide.name
          provides << { :name => provide.name, :version => provide.version.v }
        end
        print  "Success:".green
        provides.each do | provide |
          print "\n    "
          print "#{provide[:name]}".ljust(50).light_blue
          unless provide[:version] == ""
            print " >= "
            print "#{provide[:version]}".light_blue
          end
        end
        print "\n"
      end

    end
  end
end

# Create local repo
# Yum tests
print "\n*************\n".light_blue
print "* Yum tests *\n".light_blue
print "*************\n".light_blue
file = File.open("/etc/yum.repos.d/local.repo", "w")
file.write(<<-CONF.gsub(/^ {2}/, ''))
  [local]
  name=local
  baseurl=file:///builds/#{namespace}/#{project}
  gpgcheck=1
  gpgkey=file:///tmp/public
  enabled=1
CONF
file.close
commands = {
  'Creating local yum repo.......' => 'createrepo -d .',
  'Clearing yum cache............' => 'yum clean expire-cache' }
commands.each do |key, value|
  command_desc = key
  command = value
  print "#{command_desc}"
  outputs = ''
  errors =  ''
  command_status = POpen4::popen4(command) do |stdout, stderr, stdin|
    stdout.each do |line|
      outputs << "#{line.strip}\n"
    end
    stderr.each do |line|
      errors << "#{line.strip}\n"
    end
  end
  if command_status.exitstatus == 0
    print "Success: Action completed.\n".green
  else
    print "Failure:\n".red
    print "#{outputs.strip}\n".red
    print "#{errors.strip}\n".red
    global_status = command_status.exitstatus
  end
end

packages.each_value do |package|
  package_name = package[:name]
  print "Yum tests for #{package_name.light_blue}:\n"
  #Remove conflicting packages
  unless package[:conflicts].nil?
    conflicts = package[:conflicts]
    conflicts.each do |conflict|
      command = "yum remove -y #{conflict}"
      print "  Removing conflicting package #{conflict}....."
      outputs = ''
      errors =  ''
      command_status = POpen4::popen4(command) do |stdout, stderr, stdin|
        stdout.each do |line|
          outputs << "#{line.strip}\n"
        end
        stderr.each do |line|
          errors << "#{line.strip}\n"
        end
      end
      if command_status.exitstatus == 0
        print "Success: Removed.\n".green
      else
        print "Failure:\n".red
        print "#{outputs.strip}\n".red
        print "#{errors.strip}\n".red
        global_status = command_status.exitstatus
      end
    end
  end
  #RPM installs via yum?
  command = "yum install -y rubygem-#{package_name}"
  print "  RPM installs using yum?....."
  outputs = ''
  errors =  ''
  command_status = POpen4::popen4(command) do |stdout, stderr, stdin|
    stdout.each do |line|
      outputs << "#{line.strip}\n"
    end
    stderr.each do |line|
      errors << "#{line.strip}\n"
    end
  end
  if command_status.exitstatus == 0
    print "Success: Installed.\n".green
  else
    print "Failure:\n".red
    print "#{outputs.strip}\n".red
    print "#{errors.strip}\n".red
    global_status = command_status.exitstatus
  end
  #RPM is installed?
  command = "yum list installed rubygem-#{package_name}"
  print "  RPM is installed?..........."
  outputs = ''
  errors =  ''
  command_status = POpen4::popen4(command) do |stdout, stderr, stdin|
    stdout.each do |line|
      outputs = "#{line.strip}"
    end
    stderr.each do |line|
      errors << "#{line.strip}\n"
    end
  end
  if command_status.exitstatus == 0
    print "Success: #{outputs.squeeze(" ")}\n".green
  else
    print "Failure:\n".red
    print "#{outputs.strip}\n".red
    print "#{errors.strip}\n".red
    global_status = command_status.exitstatus
  end
  #unless package[:conflicts].nil?
  #  command = "yum remove -y rubygem-#{package_name}"
  #  print "  Remove RPM to avoid conflicts....."
  #  outputs = ''
  #  errors =  ''
  #  command_status = POpen4::popen4(command) do |stdout, stderr, stdin|
  #    stdout.each do |line|
  #      outputs << "#{line.strip}\n"
  #    end
  #    stderr.each do |line|
  #      errors << "#{line.strip}\n"
  #    end
  #  end
  #  if command_status.exitstatus == 0
  #    print "Success: Removed.\n".green
  #  else
  #    print "Failure:\n".red
  #    print "#{outputs.strip}\n".red
  #    print "#{errors.strip}\n".red
  #    global_status = command_status.exitstatus
  #  end
  #end
end

exit global_status

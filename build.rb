require "bundler/setup"
require "rpm"
require "fpm"
require "yaml"
require "colorize"
require "popen4"
require "fileutils"
require "pathname"
require "filesize"
require "net/http"
require 'rubygems/package'
require 'zlib'
require 'ruby_expect'

TAR_LONGLINK = '././@LongLink'

repo_name = ENV['CI_PROJECT_NAME']
repo_url_base = ENV['REPO_URL_BASE']
repo_folder = ENV['REPO_FOLDER']
homepage = ENV['CI_PROJECT_URL']
gpg_name = ENV['GPG_NAME']
gpg_file_name = ENV['GPG_FILE_NAME']
gpg_private_key = ENV['GPG_PRIVATE_KEY']
gpg_public_key = ENV['GPG_PUBLIC_KEY']
gpg_pass_phrase = ENV['GPG_PASS_PHRASE']
gpg_key_id = ENV['GPG_KEY_ID']

default_dependencies = ['ruby']
pad_length = 38
$stdout.sync = true

# Functions
# Function to convert (yaml) object to has with symbol keys
def symbolize(obj)
    return obj.inject({}){|memo,(k,v)| memo[k.to_sym] =  symbolize(v); memo} if obj.is_a? Hash
    return obj.inject([]){|memo,v    | memo           << symbolize(v); memo} if obj.is_a? Array
    return obj
end

# Function to compare two RPMs
def compare_rpms(rpm_file1, rpm_file2)
  rpm1 = XRPM::Package.open(rpm_file1)
  rpm2 = XRPM::Package.open(rpm_file2)
  
  # Name
  unless rpm1.name == rpm2.name
    puts "Debug 1: #{rpm1.name} != #{rpm2.name}"
    return false
  end

  # Version
  unless rpm1.version.v == rpm2.version.v
    puts "Debug 2: #{rpm1.version.v} != #{rpm2.version.v}"
    return false
  end

  # File sizes:
  #   - Can't use md5s due to changes to timestamps
  #   - Can't compare sizes of compiled artefacts due to subtle differences.
  #if rpm1.arch == 'noarch' or rpm2.arch == 'noarch'
  #  sizes1 =[]
  #  sizes2 =[]
  #  rpm1.files.each do |file|
  #    sizes1 << file.size
  #  end
  #  rpm2.files.each do |file|
  #    sizes2 << file.size
  #  end
  #  unless sizes1.sort == sizes2.sort
  #    puts "Debug 3: #{sizes1.sort} != #{sizes2.sort}"
  #    return false
  #  end
  #end

  # Requires
  requires1 =[]
  requires2 =[]
  rpm1.requires.each do |require|
    requires1 << {:name => require.name, :version => require.version.v, :flags => require.flags}
  end
  rpm2.requires.each do |require|
    requires2 << {:name => require.name, :version => require.version.v, :flags => require.flags}
  end
  unless requires1.sort_by {|h| h[:name]} == requires2.sort_by {|h| h[:name]}
    "Debug 4: Requires not equal"
    return false
  end

  # Provides
  provides1 =[]
  provides2 =[]
  rpm1.provides.each do |provide|
    provides1 << {:name => provide.name, :version => provide.version.v, :flags => provide.flags}
  end
  rpm2.provides.each do |provide|
    provides2 << {:name => provide.name, :version => provide.version.v, :flags => provide.flags}
  end
  unless provides1.sort_by {|h| h[:name]} == provides2.sort_by {|h| h[:name]}
    "Debug 5: Provides not equal"
    return false
  end

  # GPG Key
  gpgs = {
  "#{rpm_file1}" => '',
  "#{rpm_file2}" => ''
  }

  gpgs.each do |rpm, gpgkey|
    outputs = ''
    errors = ''
    command_status = POpen4::popen4("rpm -K #{rpm} -v")  do |stdout, stderr, stdin|
      stdout.each do |line|
        outputs << "#{line.strip}\n"
      end
      stderr.each do |line|
        errors << "#{line.strip}\n"
      end
    end
    if outputs =~ /^.*key ID .*\:.*$/i
      gpgs["#{rpm}"] = /^.*key ID (.*)\:.*$/.match(outputs).captures[-1]
    else
      gpgs["#{rpm}"] = ''
    end
  end
  unless gpgs["#{rpm_file1}"] == gpgs["#{rpm_file2}"]
    "Debug 6: GPGs not equal"
    return false
  end

  return true
end

# Function to check if a URL is valid
def url_exist?(url_string)
  url = URI.parse(url_string)
  req = Net::HTTP.new(url.host, url.port)
  req.use_ssl = (url.scheme == 'https')
  path = url.path
  res = req.request_head(path || '/')
  res.code != "404" # false if returns 404 - not found
  rescue Errno::ENOENT
  false # false if can't find the server
end

# Function to check if an RPM exists via web access (cycling through iterations)
# Returns filename and iteration number
def rpm_exist?(repo_url_base, rpm)
  components = rpm.split('-')
  name = components[0..-3].join('-')
  ver = components[-2]
  it_arch_ext = components[-1]
  ext = it_arch_ext.split('.')[-1]
  arch = it_arch_ext.split('.')[-2]
  iteration_text = it_arch_ext.split('.')[-3]

  for i in 1..20
    filename = "#{name}-#{ver}-#{i}.#{iteration_text}.#{arch}.#{ext}"
    if url_exist?("#{repo_url_base}#{filename}")
      return {:filename => filename, :iteration_number => i}
    end
  end
  return false
end

# Function to download file from web.  Returns filename.
def download_file(url_string)
  url = URI.parse(url_string)
  path = url.path
  file_name = "#{path.split('/')[-1]}.downloaded"
  File.open(file_name,'w'){ |f|
    req = Net::HTTP.new(url.host,url.port)
    req.use_ssl = (url.scheme == 'https')
    req.request_get(url.path){ |res| 
      res.read_body{ |seg|
        f << seg
        sleep 0.005 
      }
    }
  }
  return file_name
end

def unzip (tar_gz_archive)

  destination = '.'

  Gem::Package::TarReader.new( Zlib::GzipReader.open tar_gz_archive ) do |tar|
    dest = nil
    tar.each do |entry|
      if entry.full_name == TAR_LONGLINK
        dest = File.join destination, entry.read.strip
        next
      end
      dest ||= File.join destination, entry.full_name
      if entry.directory?
        FileUtils.rm_rf dest unless File.directory? dest
        FileUtils.mkdir_p dest, :mode => entry.header.mode, :verbose => false
      elsif entry.file?
        FileUtils.rm_rf dest unless File.file? dest
        File.open dest, "wb" do |f|
          f.print entry.read
        end
        FileUtils.chmod entry.header.mode, dest, :verbose => false
      elsif entry.header.typeflag == '2' #Symlink!
        File.symlink entry.header.linkname, dest
      end
      dest = nil
    end
  end
end

# Function to convert Ruby gem to RPM
def gem2rpm (name, options = {})
  default_options = {:maintainer => 'local maintainer',
                     :version => 'latest', :iteration => '1.el7', 
                     :dependencies => [], :provides => [], :conflicts => [],
                     :vendor => 'default', :replace_dependencies => false}
  options = default_options.merge(options)
  default_dependencies = ['ruby']
  gem = FPM::Package::Gem.new
  gem.maintainer = options[:maintainer]
  gem.attributes[:prefix] = '/usr/share/gems'
  gem.attributes[:gem_bin_path] = '/usr/bin'
  unless options[:version] == 'latest'
    gem.version = options[:version]
  end
  gem.iteration = options[:iteration]
  gem.input(name)
  unless options[:dependencies] == []
    if options[:replace_dependencies]
      gem.dependencies = options[:dependencies]
    else
      gem.dependencies.concat(options[:dependencies])
    end
  end
  gem.dependencies.concat(default_dependencies)
  rpm = gem.convert(FPM::Package::RPM)
  output = "NAME-VERSION-ITERATION.ARCH.rpm"
  if rpm.description.nil?
    rpm.description = 'No description supplied'
  end
  if rpm.url.nil? || 'unknown'.casecmp(rpm.url.strip) == 0
    rpm.url = "https://rubygems.org/gems/#{name}"
  end
  unless options[:version] == 'latest'
    rpm.version = options[:version]
  end
  unless options[:vendor] == 'default'
    rpm.vendor = options[:vendor]
  end
  unless options[:provides] == []
   rpm.provides.concat(options[:provides])
  end
  unless options[:conflicts] == []
   rpm.conflicts.concat(options[:conflicts])
  end
  rpm.output(rpm.to_s(output))
  rpm.cleanup
  gem.cleanup
  return "#{rpm.name}-#{rpm.version}-#{rpm.iteration}.#{rpm.architecture}.rpm"
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
    return outputs.strip
  else
    return false
  end
end

# Function to get bootstrap glyph for filetype
def get_icon(file)
  if File.ftype(file) == 'directory'
    icon = "<span class='glyphicon glyphicon-folder-open'></span>"
  else
    if File.extname(file) == '.rpm'
      icon = "<span class='glyphicon glyphicon-gift'></span>"
    else
      icon = "<span class='glyphicon glyphicon-file'></span>"
    end
  end
  return icon
end

# Function to get system ready to sign RPM files
def setup_gpg(gpg_name, private_key, public_key)
  file = File.open("#{ENV['HOME']}/.rpmmacros", "w")
  file.write(<<-RPMMACROS.gsub(/^ {6}/, ''))
    %_signature gpg
    %_gpg_path /root/.gnupg
    %_gpg_name #{gpg_name}
    %_gpgbin /usr/bin/gpg
    %_gpg_digest_algo sha256
  RPMMACROS
  file.close
  file = File.open("/tmp/private", "w")
  file.write(private_key)
  file.close
  file = File.open("/tmp/public", "w")
  file.write(public_key)
  file.close
  commands = {
  'Importing GPG private key.......' => 'gpg --allow-secret-key-import --import /tmp/private',
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

# Function to sign RPM file
def sign_rpm(rpm_file, pass_phrase, key_id)
  until rpm_is_signed?(rpm_file, key_id)
    command = "rpm --resign #{rpm_file}"
    exp = RubyExpect::Expect.spawn(command)
    exp.procedure do
      each do
        expect 'Enter pass phrase:' do
          send pass_phrase
        end
      end
    end
  end
end

# Function to check if package is package is signed correctly
def rpm_is_signed?(rpm_file, key_id)
  outputs = ''
  errors = ''
  found_key = ''
  command_status = POpen4::popen4("rpm -K #{rpm_file} -v")  do |stdout, stderr, stdin|
    stdout.each do |line|
      outputs << "#{line.strip}\n"
    end
    stderr.each do |line|
      errors << "#{line.strip}\n"
    end
  end
  if outputs =~ /^.*key ID .*\:.*$/i
    found_key = /^.*key ID (.*)\:.*$/.match(outputs).captures[-1]
  end
  if found_key == key_id
    return true
  else
    return false
  end
end

# Function to render HTML directory listings
def render_html(path, level = 0, repo_url_base)
  if File.directory?(path)
    pn = Pathname.new(path)
    dir_name = "/#{Pathname(pn).each_filename.to_a[2..-1].join('/')}"
    file = File.open("#{pn}/index.html", "a")
    file.write(<<-HTML.gsub(/^ {6}/, ''))
      <!DOCTYPE html>
      <html>
        <head>
          <title>ergel</title>
          <script type='text/javascript'>
            if(window.location.protocol != 'https:') {
              location.href = location.href.replace("http://", "https://");
            }
          </script>
          <link href='#{"../"*level}bower_components/bootstrap/dist/css/bootstrap.min.css'
                rel='stylesheet'>
          <link href='#{"../"*level}bower_components/bootstrap/dist/css/bootstrap-theme.min.css'
                rel='stylesheet'>
          <link href='#{"../"*level}bower_components/components-font-awesome/css/font-awesome.min.css'
                rel='stylesheet'>
          <link href='#{"../"*level}theme.css' rel='stylesheet'>
          <link rel='icon' href='#{"../"*level}favicon.png'>
        </head>
        <body>
          <nav class='navbar navbar-inverse navbar-fixed-top'>
            <div class='container'>
              <div class='navbar-header'>
                <button type='button' class='navbar-toggle collapsed'
                        data-toggle='collapse' data-target='#navbar'
                        aria-expanded='false' aria-controls='navbar'>
                  <span class='sr-only'>Toggle navigation</span>
                  <span class='icon-bar'></span>
                  <span class='icon-bar'></span>
                  <span class='icon-bar'></span>
                </button>
              </div>
              <div id='navbar' class='navbar-collapse collapse'>
                <ul class='nav navbar-nav navbar-left'>
                  <li>
                    <a href='#{"../"*level}../harbottle-main#'>
                      harbottle-main <span class='sr-only'>(current)</span>
                    </a>
                  </li>
                  <li>
                    <a href='#{"../"*level}../epmel#'>
                      epmel <span class='sr-only'>(current)</span>
                    </a>
                  </li>
                  <li class='active'>
                    <a href='#{"../"*level}#'>
                      ergel <span class='sr-only'>(current)</span>
                    </a>
                  </li>
                  <li>
                    <a href='#{"../"*level}../epypel#'>
                      epypel <span class='sr-only'>(current)</span>
                    </a>
                  </li>
                </ul>
                <ul class='nav navbar-nav navbar-right'>
    HTML
    if File.exist?("#{pn}/ergel-release.rpm")
      file.write(<<-HTML.gsub(/^ {6}/, ''))
                  <li>
                    <a href='ergel-release.rpm'>
                      Release RPM Permalink
                    </a>
                  </li>
      HTML
    end
    file.write(<<-HTML.gsub(/^ {6}/, ''))
                  <li>
                    <a href='#{"../"*level}RPM-GPG-KEY-harbottle'>
                      GPG key
                    </a>
                  </li>
                  <li>
                    <a href='https://gitlab.com/harbottle/ergel/issues/new'>
                      Request a gem
                    </a>
                  </li>
                  <li>
                    <a href='https://gitlab.com/harbottle/ergel'>About</a>
                  </li>
                  <li>
                    <a href='https://twitter.com/liger1978'>
                       Contact
                       <i class='fa fa-twitter' aria-hidden='true'></i>
                    </a>
                  </li>
              </div>
            </div>
          </nav>
          <div class='container theme-showcase' role='main'>
    HTML
    if level == 0
      file.write(<<-HTML.gsub(/^ {6}/, ''))
            <div class='jumbotron'>
              <h1>ergel</h1>
              <p><b>E</b>xtra <b>R</b>uby <b>G</b>ems for <b>E</b>nterprise <b>L</b>inux<br />(Beta)</p>
            </div>
      HTML
    end
    file.write(<<-HTML.gsub(/^ {6}/, ''))
            <div class='page-header'>
              <div class='panel panel-primary'>
                <div class='panel-heading'>#{dir_name}</div>
                <table class='table'>
                  <thead>
                    <tr>
                      <th>&nbsp;</th>
                      <th>&nbsp;</th>
                      <th>File&nbsp;name</th>
                      <th>File&nbsp;size</th>
                    </tr>
                  </thead>
                  <tbody>
    HTML
    if level > 0
      file.write(<<-HTML.gsub(/^ {6}/, ''))
                    <tr>
                      <td>
                      </td>
                      <td>
                        <a href='..'>
                          <span class='glyphicon glyphicon-level-up'></span>
                        </a>
                      </td>
                      <td><a href='..'>..</a></td>
                      <td>&nbsp;</td>
                    </tr>
      HTML
    end
    files = Dir.glob("#{pn}/*").select { |x| File.ftype(x) == 'file' }.sort
    dirs = Dir.glob("#{pn}/*").select { |x| File.ftype(x) == 'directory' }.sort
    #Dir.glob("#{pn}/*") do | subpath |
    (dirs + files).each do | subpath |
      spn = Pathname.new(subpath)
      filesize = (Filesize.from("#{File.size?(subpath)} B").pretty).gsub(' ','&nbsp;')
      if "#{spn.basename}" != 'index.html'
        file.write(<<-HTML.gsub(/^ {6}/, ''))
                    <tr>
                      <td>
        HTML
        if !url_exist?("#{repo_url_base}#{dir_name}/#{spn.basename}")
          file.write(<<-HTML.gsub(/^ {6}/, ''))
                        <a href="#{spn.basename}">
                          <span class="label label-success label-as-badge">
                            New!
                          </span>
                        </a>
            HTML
          end
        file.write(<<-HTML.gsub(/^ {6}/, ''))
                      </td>
                      <td>
                        <a href='#{spn.basename}'>
                          #{get_icon(subpath)}
                        </a>
                      </td>
                      <td>
                        <div class='truncate-ellipsis'>
                          <span>
                            <a href='#{spn.basename}'>#{spn.basename}</a>
                          </span>
                        </div>
                      </td>
                      <td>
                        <a href='#{spn.basename}'>#{filesize}</a>
                      </td>
                    </tr>
        HTML
      end
      render_html(subpath, level + 1, repo_url_base)
    end
    file.write(<<-HTML.gsub(/^ {6}/, ''))
                  </tbody>
                </table>
              </div><!-- class='panel panel-primary' -->
            </div><!-- class='page-header' -->
          </div><!-- class='container theme-showcase' -->
          <div class='footer'>
            <div class='container text-center'>
              <p>
                <a href='#{"../"*level}#'>
                  ergel
                </a> last updated #{Time.utc(*Time.new.to_a)}</p>
              </p>
            </div><!-- class='container text-center' -->
          </div><!-- class='footer' -->
        </body>
        <script src='#{"../"*level}bower_components/jquery/dist/jquery.min.js'></script>
        <script src='#{"../"*level}bower_components/bootstrap/dist/js/bootstrap.min.js'></script>
        <script>
          (function(i,s,o,g,r,a,m){i['GoogleAnalyticsObject']=r;i[r]=i[r]||function(){
          (i[r].q=i[r].q||[]).push(arguments)},i[r].l=1*new Date();a=s.createElement(o),
          m=s.getElementsByTagName(o)[0];a.async=1;a.src=g;m.parentNode.insertBefore(a,m)
          })(window,document,'script','https://www.google-analytics.com/analytics.js','ga');
          ga('create', 'UA-88201102-1', 'auto');
          ga('send', 'pageview');
        </script>
      </html>
    HTML
    file.close
  end
end

def create_release_rpm( name, yum_description, rpm_description, version,
                        iteration, vendor, maintainer, yum_url, rpm_url,
                        public_key, public_key_name )
  FileUtils::mkdir_p './release/etc/yum.repos.d'
  FileUtils::mkdir_p './release/etc/pki/rpm-gpg'
  file = File.open("./release/etc/yum.repos.d/#{name}.repo", "w")
  file.write(<<-REPO.gsub(/^ {4}/, ''))
    [#{name}]
    name=#{yum_description}
    baseurl=#{yum_url}
    gpgcheck=1
    gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-#{public_key_name}
    enabled=1
    REPO
  file.close
  file = File.open("./release/etc/pki/rpm-gpg/RPM-GPG-KEY-#{public_key_name}", "w")
  file.write(public_key)
  file.close
  dir = FPM::Package::Dir.new
  dir.name = "#{name}-release"
  dir.description = rpm_description
  dir.version = version
  dir.iteration = iteration
  dir.vendor = vendor
  dir.maintainer = maintainer
  dir.url = rpm_url
  dir.attributes[:chdir] = "#{FileUtils::pwd}/release"
  dir.input('etc')
  dir.config_files << "/etc/yum.repos.d/#{name}.repo"
  rpm = dir.convert(FPM::Package::RPM)
  output = "NAME-VERSION-ITERATION.ARCH.rpm"
  rpm.output(rpm.to_s(output))
  rpm.cleanup
  dir.cleanup
end

# Main code
# Convert Ruby gems
setup_gpg(gpg_name, gpg_private_key, gpg_public_key)
yaml = YAML::load_file(File.join(__dir__, 'packages.yml'))
yaml = symbolize(yaml)
maintainer = yaml[:maintainer] || 'example@example.com'
print "Package maintainer set to #{maintainer.light_blue}.\n"
gems = yaml[:packages]
gems.each_value do |gem|
  name = gem[:name]
  options = {:maintainer => maintainer}.merge(gem)
  print name.ljust(pad_length, padstr='.').light_blue
  repo = pkg_in_yum?("rubygem-#{name}")
  if repo && !options[:force_new_version]    
    print "Skipped: Pkg exists in ".yellow
    print repo.light_blue
    print " repo.\n".yellow
  else
    new_rpm = gem2rpm(name, options)
    sign_rpm(new_rpm, gpg_pass_phrase, gpg_key_id)
    published_rpm = rpm_exist?("#{repo_url_base}/#{repo_folder}",new_rpm)
    if published_rpm
      downloaded_rpm = download_file("#{repo_url_base}/#{repo_folder}#{published_rpm[:filename]}")
      if compare_rpms(new_rpm,downloaded_rpm)
        FileUtils::rm_f new_rpm
        new_rpm = downloaded_rpm.gsub '.downloaded', ''
        FileUtils::mv downloaded_rpm, new_rpm
        new_pkg_notify = 'Identical file.'
      else
        options[:iteration] = "#{published_rpm[:iteration_number] + 1}.el7"
        FileUtils::rm_f new_rpm
        FileUtils::rm_f downloaded_rpm
        new_rpm = gem2rpm(name, options)
        sign_rpm(new_rpm, gpg_pass_phrase, gpg_key_id)
        new_pkg_notify = 'New iteration!'
      end
    else
      new_pkg_notify = 'New pkg or version!'
    end
    print new_rpm.ljust(62).green
    print new_pkg_notify.light_blue
    print "\n"
  end
end

# Create release RPM
yum_description = 'Extra Ruby Gems for Enterprise Linux 7'
rpm_description = <<-DESC.gsub(/^ {2}/, '')
  Extra Ruby Gems for Enterprise Linux repository configuration.
  This package includes the GPG Key as well as configuration for yum.
  DESC
create_release_rpm( repo_name, yum_description, rpm_description, '7',
                    '2.el7', maintainer, maintainer, "#{repo_url_base}/#{repo_folder}", homepage,
                    gpg_public_key, gpg_file_name )

# Create public directory and copy RPMs
FileUtils::rm_rf './public'
FileUtils::mkdir_p './public/7/x86_64'
FileUtils.cp Dir.glob('./*.rpm'), './public/7/x86_64'

# Create yum repo
print "\n"
print "Build public yum repo...".ljust(pad_length-14, padstr='.')
outputs = ''
errors = ''
command_status = POpen4::popen4("cd .; createrepo -d public/7/x86_64")  do |stdout, stderr, stdin|
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
  print "Failure:\n#{errors}\n".red
  exit 1
end

# Create release RPM symlink
Dir.chdir("./public/7/x86_64") do
  target_rpm = Dir.glob("./**/ergel-release*.rpm")[0]
  File.symlink(target_rpm, "ergel-release.rpm")
end

# Create directory listings
print "Build public dir listings...".ljust(pad_length-14, padstr='.')
render_html('./public', 0, repo_url_base)
print "Success.\n".green

# Copy other web assets
print "Build public assets...".ljust(pad_length-14, padstr='.')
FileUtils.cp 'theme.css', 'public/theme.css'
FileUtils.cp 'favicon.png', 'public/favicon.png'
file = File.open("public/RPM-GPG-KEY-harbottle", "w")
file.write(ENV['GPG_PUBLIC_KEY'])
file.close
print "Success.\n".green

# Install bootstrap etc.
print "Build public vendor components...".ljust(pad_length-14, padstr='.')
FileUtils.cp 'bower.json', 'public/bower.json'
command_status = POpen4::popen4("cd public; bower --allow-root install")  do |stdout, stderr, stdin|
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
  print "Failure:\n#{errors}\n".red
  exit 1
end

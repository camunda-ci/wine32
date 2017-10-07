require "fileutils"
require "filesize"
require "pathname"
require "net/http"

repo_url_base = ENV['REPO_URL_BASE']
$stdout.sync = true

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
          <title>wine32</title>
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
                  <li class='active'>
                    <a href='#{"../"*level}#'>
                      wine32 <span class='sr-only'>(current)</span>
                    </a>
                  </li>
                  <li>
                    <a href='#{"../"*level}../epmel#'>
                      epmel <span class='sr-only'>(current)</span>
                    </a>
                  </li>
                  <li>
                    <a href='#{"../"*level}../ergel#'>
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
    if File.exist?("#{pn}/wine32-release.rpm")
      file.write(<<-HTML.gsub(/^ {6}/, ''))
                  <li>
                    <a href='wine32-release.rpm'>
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
                    <a href='https://gitlab.com/harbottle/wine32/issues/new'>
                      Request a package
                    </a>
                  </li>
                  <li>
                    <a href='https://gitlab.com/harbottle/wine32'>About</a>
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
              <h1>wine32</h1>
              <p>Wine 32 bit packages for Enterprise Linux<br />(Beta)</p>
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
                  wine32
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

# Main code
# Create directory listings
print "Build public dir listings..."
render_html('./public', 0, repo_url_base)
print "Success.\n"

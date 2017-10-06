task :default => [:build]

task :build do
    ruby "build.rb"
end

task :test do
    ruby "test_rpm.rb"
    sh "python test_ruby.py"
end

task :deploy do
    ruby "deploy.rb"
end

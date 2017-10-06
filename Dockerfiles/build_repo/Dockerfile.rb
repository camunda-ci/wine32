FROM centos:latest
MAINTAINER harbottle <grainger@gmail.com>
RUN yum -y install http://harbottle.gitlab.io/harbottle-main-release/harbottle-main-release-7.rpm
RUN yum -y install epel-release
RUN yum -y install rubygems
RUN yum -y install ruby-devel
RUN yum -y install rpm-build 
RUN yum -y install gcc 
RUN yum -y install gcc-c++ 
RUN yum -y install make 
RUN yum -y install wget
RUN yum -y install createrepo
RUN yum -y install git
RUN yum -y install rpm-sign
RUN yum -y install lxc-devel
RUN yum -y install zlib-devel
RUN yum -y install nodejs-bower
RUN gem install bundler --no-rdoc --no-ri

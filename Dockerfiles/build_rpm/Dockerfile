FROM harbottle/centos7i386:latest
MAINTAINER harbottle <grainger@gmail.com>
RUN yum -y install rpm-build
RUN yum -y install yum-utils
RUN yum -y install rpmdevtools
RUN yum -y groupinstall "Development Tools"
RUN sed -i -e 's/altarch/centos/g' /etc/yum.repos.d/CentOS-Sources.repo
RUN yum -y install http://mirror.centos.org/centos/7/extras/x86_64/Packages/epel-release-7-9.noarch.rpm
RUN yum -y install expect
RUN yum -y install createrepo

# 32 bit Wine packages for Enterprise Linux

**[Browse the yum repo.](https://harbottle.gitlab.io/wine32/7/i386)**

A yum repo of RPM files containing 32 bit Wine packages. The packages are
suitable for CentOS 7 (and RHEL, Oracle Linux, etc.).

Packages have been rebuilt from  the standard wine source RPMs available in
[EPEL](https://fedoraproject.org/wiki/EPEL) using
[GitLab CI](https://about.gitlab.com/gitlab-ci/). The yum repo is hosted
courtesy of [GitLab Pages](https://pages.gitlab.io/).

## Quick Start

```bash
# Install the repo
sudo yum -y install https://harbottle.gitlab.io/wine32/7/i686/wine32-release.rpm

# Install Wine 32 bit
sudo yum -y install wine.i686
```

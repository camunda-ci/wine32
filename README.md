# **ergel**: Extra Ruby Gems for Enterprise Linux

**[Browse the yum repo.](https://harbottle.gitlab.io/ergel/7/x86_64)**

A yum repo of RPM files containing Ruby [gems](https://rubygems.org/)
not available in the standard repos. The packages are suitable for CentOS 7 (and
RHEL, Oracle Linux, etc.). Ensure you also have the
[EPEL](https://fedoraproject.org/wiki/EPEL) repo enabled.

Gems are converted automatically using
[GitLab CI](https://about.gitlab.com/gitlab-ci/) and the excellent
[fpm](https://github.com/jordansissel/fpm) gem.  The yum repo is hosted
courtesy of [GitLab Pages](https://pages.gitlab.io/).

## Quick Start

```bash
# Install the EPEL repo
sudo yum -y install epel-release

# Install the ergel repo
sudo yum -y install https://harbottle.gitlab.io/ergel/7/x86_64/ergel-release.rpm
```

After adding the repo to your system, you can install
[available packages](https://harbottle.gitlab.io/ergel/7/x86_64) using `yum`.

## Why?
ERGEL is an easy way to install Ruby gems on your CentOS box using the
native `yum` package manager.  Additional gems can be easily added to the
[`packages.yml`](packages.yml) file to expand the repo in line with user needs.

## Adding gems to the repo

[File a new issue](https://gitlab.com/harbottle/ergel/issues/new).
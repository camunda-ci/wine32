Name:           wine32-release
Version:        7
Release:        2.el7
Summary:        Wine 32 bit packages for Enterprise Linux repository configuration
Group:          System Environment/Base
License:        MIT
URL:            https://gitlab.com/harbottle/wine32
Source0:        RPM-GPG-KEY-harbottle-wine32
Source1:        MIT
Source2:        wine32.repo

BuildArch:     noarch
Requires:      redhat-release >=  7

%description
This package contains the Wine 32 bit packages for Enterprise Linux
repository GPG key as well as configuration for yum.

%prep
%setup -q  -c -T
install -pm 644 %{SOURCE0} .
install -pm 644 %{SOURCE1} .

%build

%install
rm -rf $RPM_BUILD_ROOT
install -Dpm 644 %{SOURCE0} $RPM_BUILD_ROOT%{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-harbottle-wine32
install -dm 755 $RPM_BUILD_ROOT%{_sysconfdir}/yum.repos.d
install -pm 644 %{SOURCE2} $RPM_BUILD_ROOT%{_sysconfdir}/yum.repos.d

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root,-)
%doc MIT
%config(noreplace) /etc/yum.repos.d/*
/etc/pki/rpm-gpg/*

%changelog
* Mon Oct 9 2017 <grainger@gmail.com> - 7-2.el7
- Add SRPM repo

* Sat Oct 7 2017 <grainger@gmail.com> - 7-1.el7
- Initial packaging

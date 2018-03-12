Name:           ess-ceph-utils
Version:        0.0.1
Release:        1%{?dist}
Summary:        Easystack storage serivce utilities for ceph

License:	ASL 2.0
URL:            https://easystack.cn/
Source0:        esstorage-udev-disk-hotplug
Source1:        99-esstorage.rules

Requires:       docker-ce
Requires:       kmod

%description
The ess-ceph-utils package provides some tools for ceph.

%global _udevlibdir %{_prefix}/lib/udev

%build


%install
install -d %{buildroot}%{_udevlibdir}
install -D -p -m 755 %{SOURCE0} %{buildroot}%{_udevlibdir}
install -d %{buildroot}%{_udevrulesdir}
install -p -m 644 %{SOURCE1} %{buildroot}%{_udevrulesdir}


%files
%{_udevlibdir}/*
%{_udevrulesdir}/*


%changelog

* Tue Mar 03 2018 Linggang Zeng <linggang.zeng@easystack.cn> - 0.0.1-1
- Initial build

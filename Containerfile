# TODO: Fix tar on Fedora 40
FROM registry.fedoraproject.org/fedora:39 AS builder

RUN dnf install --disablerepo='*' --enablerepo='fedora,updates' --setopt install_weak_deps=0 --nodocs --assumeyes rpm-build systemd-rpm-macros wget jq git

ADD https://codeberg.org/fabiscafe/game-devices-udev/archive/main.tar.gz /tmp/ublue-os/rpmbuild/SOURCES/game-devices-udev.tar.gz

# Add udev rules from repository
ADD files/etc/udev/rules.d /tmp/ublue-os/udev-rules/etc/udev/rules.d

# Install Sunshine udev rules from their github repo
RUN mkdir -p /tmp/Sunshine/ && \
mkdir -p /etc/udev/rules.d/ && \
pushd /tmp/Sunshine && \
git clone --depth 1 https://github.com/LizardByte/Sunshine . && \
mv /tmp/Sunshine/src_assets/linux/misc/60-sunshine.rules /tmp/ublue-os/udev-rules/etc/udev/rules.d/60-sunshine-ublue.rules && \
popd && \
rm -rf /tmp/Sunshine

# Install Framework Computer udev rules from their inputmodule-rs package
RUN mkdir -p /etc/udev/rules.d/ && \
wget https://raw.githubusercontent.com/FrameworkComputer/inputmodule-rs/main/release/50-framework-inputmodule.rules -O /tmp/ublue-os/udev-rules/etc/udev/rules.d/50-framework-inputmodule.rules

ADD files/etc/rpm-ostreed.conf /tmp/ublue-os/update-services/etc/rpm-ostreed.conf
ADD files/etc/systemd /tmp/ublue-os/update-services/etc/systemd
ADD files/usr/lib/systemd /tmp/ublue-os/update-services/usr/lib/systemd

ADD files/etc/containers /tmp/ublue-os/signing/etc/containers
ADD files/usr/etc/containers /tmp/ublue-os/signing/usr/etc/containers
ADD files/etc/pki /tmp/ublue-os/signing/etc/pki

RUN tar cf /tmp/ublue-os/rpmbuild/SOURCES/ublue-os-udev-rules.tar.gz -C /tmp ublue-os/udev-rules
RUN tar cf /tmp/ublue-os/rpmbuild/SOURCES/ublue-os-update-services.tar.gz -C /tmp ublue-os/update-services
RUN tar cf /tmp/ublue-os/rpmbuild/SOURCES/ublue-os-signing.tar.gz -C /tmp ublue-os/signing

ADD rpmspec/*.spec /tmp/ublue-os

RUN rpmbuild -ba \
    --define '_topdir /tmp/ublue-os/rpmbuild' \
    --define '%_tmppath %{_topdir}/tmp' \
    /tmp/ublue-os/*.spec
    
#This can be cleaner and put together with other RPMs in -config, I cant be bothered right now    
ADD build /tmp/build
RUN /tmp/build/ublue-os-just/build.sh
RUN /tmp/build/ublue-os-luks/build.sh

RUN mkdir /tmp/ublue-os/{files,rpms}

# Dump a file list for each RPM for easier consumption
RUN \
    for RPM in /tmp/ublue-os/rpmbuild/RPMS/*/*.rpm; do \
        NAME="$(rpm -q $RPM --queryformat='%{NAME}')"; \
        mkdir "/tmp/ublue-os/files/${NAME}"; \
        rpm2cpio "${RPM}" | cpio -idmv --directory "/tmp/ublue-os/files/${NAME}"; \
        cp "${RPM}" "/tmp/ublue-os/rpms/$(rpm -q "${RPM}" --queryformat='%{NAME}.%{ARCH}.rpm')"; \
    done

FROM scratch

# Copy build RPMs
COPY --from=builder /tmp/ublue-os/rpms /rpms
# Copy dumped RPM content
COPY --from=builder /tmp/ublue-os/files /files

#!/bin/bash
trap 'rm -rf "${BUILDDIR}"; kill 0' SIGINT SIGTERM EXIT
export BUILDDIR=$(mktemp -d)

ARCH=amd64
SUITE=precise
VARIANT=minbase

VMHOSTNAME=localhost.localdomain

CLOUDUTILS="yes"
OUTFORMAT="qcow2"

export DEBIAN_FRONTEND=noninteractive

# FIXME: hack!
export FAKECHROOT_CMD_SUBST=/usr/bin/ldd=$HOME/Programs/bin/ldd.fakechroot

# set up build dir
RUNDIR="${PWD}"
cd ${BUILDDIR}

mkdir root

# bootstrap the environment (debootstrap needs fakechroot)
fakeroot fakechroot \
    debootstrap --arch=${ARCH} --variant=${VARIANT} ${SUITE} root

# universe needed for extlinux and dropbear
fakeroot augtool -r root -s <<EOF
set /files/etc/apt/sources.list/*[./distribution = "${SUITE}"]/component[. = "universe"] "universe"
EOF

# update needed because of changes to sources...
fakeroot fakechroot chroot root apt-get update

# empty packages for dependencies we don't want to install, at least at first
for PACKAGE in linux-firmware crda wireless-regdb; do
    fakeroot fakechroot chroot root apt-cache show ${PACKAGE} | sed '/^$/,$d' |\
        grep "^\(Package\|Version\|Provides\|Conflicts\):" > ${PACKAGE}.conf
    DEBFILE=$(equivs-build ${PACKAGE}.conf | perl -ane 'print "$1\n" if (/^dpkg-deb:.*`\.\.\/(.*)'"'"'.$/);')
    fakeroot mv ${DEBFILE} root/
    fakeroot fakechroot chroot root dpkg -i ${DEBFILE}
    fakeroot rm root/${DEBFILE}
done

# install and configure kernel
fakeroot fakechroot chroot root \
    apt-get -y -q --no-install-recommends install linux-image-virtual 

# prevent post-install scripts from starting services
fakeroot mv root/usr/sbin/invoke-rc.d .
fakeroot ln -s /bin/true root/usr/sbin/invoke-rc.d

# install additional packages
fakeroot fakechroot chroot root \
    apt-get -y -q --no-install-recommends install net-tools openssh-server

# allow services
fakeroot rm root/usr/sbin/invoke-rc.d
fakeroot mv invoke-rc.d root/usr/sbin/invoke-rc.d

# ------ BEGIN CLOUD ------
if [ "${CLOUDUTILS}" = "yes" ]; then

    fakeroot fakechroot chroot root \
        apt-get -y -q --no-install-recommends install \
            cloud-init cloud-utils cloud-initramfs-growroot

    fakeroot fakechroot chroot root useradd -m -k /etc/skel ubuntu

    KERNEL_APPEND="console=ttyS0"
fi
# ------- END CLOUD --------

# remove packages we really don't need/want
fakeroot fakechroot chroot root \
    dpkg -r --force-depends locales memtest86+

# clean up package cache
fakeroot fakechroot chroot root apt-get clean

# fix links using the real path instead of fake chroot
fakeroot find root -type l -exec \
    /bin/bash -c 'TARGET=$(readlink {}); ln -snf ${TARGET#${BUILDDIR}/root} {}' \;

# set hostname to default value
fakeroot tee root/etc/hostname <<<"${VMHOSTNAME}" >/dev/null

# set random seed value
dd if=/dev/urandom of=root/var/lib/urandom/random-seed \
    bs=8 count=1 conv=nocreat,notrunc 2>/dev/null

# remove files we don't need in the image
# NOTE: many of these taken from virt-sysprep...
fakeroot rm -rf \
    root/var/spool/cron \
    root/var/lib/dhclient/* root/var/lib/dhcp/* root/var/lib/dhcpd/* \
    root/var/log/*.log* root/var/log/audit/* root/var/log/btmp* \
    root/var/log/cron* root/var/log/dmesg* root/var/log/lastlog* \
    root/var/log/maillog* root/var/log/mail/* root/var/log/messages* \
    root/var/log/secure* root/var/log/spooler* root/var/log/tallylog* \
    root/var/log/lighttpd/* root/var/log/faillog root/var/log/lastlog \
    root/var/log/udev root/var/log/wtmp* \
    root/var/spool/mail/* root/var/mail/* \
    root/etc/sysconfig/hw-uuid root/etc/smolt/uuid root/etc/smolt/hw-uuid \
    root/etc/ssh/*_host_* root/etc/dropbear/*_host_key \
    root/etc/udev/rules.d/70-persistent-net.rules \
    root/var/lib/yum/uuid \
    root/var/lib/apt/lists/ar* root/var/cache/apt/*.bin \
    root/root/.bash_history \
    root/vmlinuz.old root/initrd.img.old \
    root/tmp/* root/dev/* root/proc/* root/sys/* root/run/*

fakeroot mkdir root/dev/pts

# add bootloader configuration
fakeroot tee root/boot/syslinux.cfg <<EOF > /dev/null
PROMPT 0
TIMEOUT 50
DEFAULT linux

LABEL linux
LINUX /vmlinuz
INITRD /initrd.img
APPEND nosplash root=/dev/xda1 ro ${KERNEL_APPEND}
EOF

# just exit with squashfs...
if [ "${OUTPUTFORMAT}" = "squashfs" ]; then
    fakeroot mksquashfs root ${RUNDIR}/${SUITE}-${VARIANT}-${ARCH}.squashfs
    exit 0
fi

# create archive in fakeroot environment
fakeroot tar -C root -czf root.tar.gz . 

# FIXME: why do we need to update again?
fakeroot fakechroot chroot root apt-get update

# install extlinux
fakeroot fakechroot chroot root apt-get -y -q install extlinux

# create archive in fakeroot environment
fakeroot tar -C root -czf extroot.tar.gz . 

guestfish <<EOF
allocate disk.img 512M
allocate extlinux.img 512M
run
part-disk /dev/sdb mbr
mkfs ext4 /dev/sdb1
mount /dev/sdb1 /
tgz-in extroot.tar.gz /
part-disk /dev/sda mbr
part-set-bootable /dev/sda 1 true
mkfs ext4 /dev/sda1
mount /dev/sda1 /mnt
tgz-in root.tar.gz /mnt
command "extlinux --install /mnt/boot"
EOF

# add syslinux to mbr
dd bs=440 conv=notrunc count=1 if=/usr/lib/syslinux/mbr.bin of=disk.img

# convert to qcow2...
qemu-img convert -c -O qcow2 disk.img ${RUNDIR}/${SUITE}-${VARIANT}-${ARCH}.qcow2

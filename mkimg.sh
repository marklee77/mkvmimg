#!/bin/bash
IMGSIZE=1G

# create image
dd if=/dev/zero of=disk.img bs=1 count=0 seek=${IMGSIZE}

# create partition table
parted -s disk.img mklabel msdos

# create boot partition
parted -s --align=none disk.img mkpart primary 0 256M

# make bootable
echo -e "a\n1\nw\nq" | fdisk disk.img

# add syslinux mbr
dd bs=440 conv=notrunc count=1 if=/usr/lib/syslinux/mbr.bin of=disk.img

# create home partition
parted -s --align=none disk.img mkpart primary 256M+1 100%

# attach loopback
sudo losetup /dev/loop0 disk.img

# add partitions
sudo kpartx -a /dev/loop0

# create filesystems
sudo mkfs -t ext4 /dev/mapper/loop0p1
sudo mkfs -t ext4 /dev/mapper/loop0p2

# mount filesystems
sudo mkdir /mnt/vmboot
sudo mount /dev/mapper/loop0p1 /mnt/vmboot

sudo mkdir /mnt/vmhome
sudo mount /dev/mapper/loop0p2 /mnt/vmhome

# install syslinux in dir
sudo extlinux --install /mnt/vmboot

# install kernel and config
sudo cp boot/* /mnt/vmboot

# install home
sudo cp -r vmuser /mnt/vmhome/

# set uid/gid
sudo chown -R 1000:100 /mnt/vmhome/vmuser

# unmount
sudo umount /mnt/vmboot
sudo rmdir /mnt/vmboot

sudo umount /mnt/vmhome
sudo rmdir /mnt/vmhome

# remove partitions
sudo kpartx -d /dev/loop0

# detach loopback
sudo losetup -d /dev/loop0

# convert to vmdk
kvm-img convert -O vmdk disk.img disk.vmdk

# add to vmx...
mv disk.vmdk OpenFoam_Client/OpenFoam_Client.vmdk

# convert to ovf
ovftool --compress OpenFoam_Client/OpenFoam_Client.vmx boot.ova

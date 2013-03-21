mkvmimg
=======

Create virtual machine boot images from a config file and some directories.

mkimg.sh is a shell script that creates a virtual machine boot disk for our
current usage scenario, where the machine root is hosted on nfs and a local
/home directory is desired. It depends on parted, kvm-img, kpartx, and ovftool,
along with standard system utilities.

mkimg.py is intended to be a configurable replacement written in python.

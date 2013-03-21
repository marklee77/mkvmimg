#!/usr/bin/env python
import parted

def size_to_bytes(size):
    import re
    r = re.compile("(\d+)([a-zA-Z]*)")
    m = r.match(size)
    v = int(m.group(1))
    u = m.group(2)
    return v * parted.__exponents.get(u, 1)

def main(argv=None):
    from argparse import ArgumentParser
    from os.path import isfile
    from yaml import load
    try:
        from yaml import CLoader as Loader
    except ImportError:
        from yaml import Loader

    parser = ArgumentParser(description="")
    parser.add_argument('-c', '--config', default=None, help='')

    args = parser.parse_args()

    if not args.config or not isfile(args.config):
        raise SystemExit("Error: must specify config file.")

    config = load(open(args.config, 'r'), Loader=Loader)

    # FIXME: should compute disk size automatically from partitions if not
    # specified, and sanity check otherwise
    for diskspec in config['disks']:
        dsize = sum(size_to_bytes(p['size']) for p in diskspec['partitions'])
        dsize = max(diskspec.get('size', dsize), dsize)

        # FIXME: add partition table type and gpt support
        # space for partition table
        dsize += 512

        # create empty disk file
        f = open('disk.img', 'w')
        f.seek(dsize - 1)
        f.write('\0')
        f.close()

        # create partitions and add file systems as appropriate
        device = parted.Device(path='disk.img')
        disk = parted.freshDisk(device, 'msdos')
        start = 1
        for partspec in diskspec['partitions']:
            # parted.sizeToSectors?
            length = size_to_bytes(partspec['size']) / device.sectorSize
            geometry = parted.Geometry(device, start=start, length=length)
            partition = parted.Partition(disk=disk, 
                                         type=parted.PARTITION_NORMAL, 
                                         geometry=geometry)
            constraint = parted.Constraint(minGeom=geometry)
            disk.addPartition(partition=partition, constraint=constraint)
            start += length

        disk.commitToDevice()

if __name__ == "__main__":
    main()

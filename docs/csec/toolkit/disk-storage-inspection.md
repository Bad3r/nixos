# Pentesting Toolkit: Disk & Storage Inspection

[Back to Pentesting Toolkit](../toolkit.md)

## Disk & Storage Inspection

- gparted
  - run..: `gparted`
  - Repo.: <https://gitlab.gnome.org/GNOME/gparted>
  - Docs.: <https://gparted.org/documentation.php>
  - Desc.: Graphical partition editor used during forensic mounting and image preparation.
- parted
  - run..: `parted $device`
  - Repo.: <https://git.savannah.gnu.org/cgit/parted.git>
  - Docs.: <https://www.gnu.org/software/parted/manual/>
  - Desc.: Command-line partition editor used during forensic mounting and image preparation.
- gnome-disk-utility
  - run..: `gnome-disks`
  - Repo.: <https://gitlab.gnome.org/GNOME/gnome-disk-utility>
  - Docs.: <https://help.gnome.org/users/gnome-help/stable/disk.html>
  - Desc.: GUI disk inspector with SMART and image creation features.
- hdparm
  - run..: `hdparm -I $device`
  - Repo.: <https://sourceforge.net/projects/hdparm/>
  - Docs.: <https://sourceforge.net/projects/hdparm/files/>
  - Desc.: Low-level ATA/SATA control; flushes caches and reads identify data.
- lshw
  - run..: `lshw -short`
  - Repo.: <https://github.com/lyonel/lshw>
  - Docs.: <https://ezix.org/project/wiki/HardwareLiSter>
  - Desc.: Hardware inventory for recording acquisition system components.
- nvme-cli
  - run..: `nvme list`
  - Repo.: <https://github.com/linux-nvme/nvme-cli>
  - Docs.: <https://github.com/linux-nvme/nvme-cli#readme>
  - Desc.: NVMe namespace, log, and self-test inspection.
- smartmontools
  - run..: `smartctl -a $device`
  - Repo.: <https://github.com/smartmontools/smartmontools>
  - Docs.: <https://www.smartmontools.org/>
  - Desc.: SMART self-tests and disk health attributes.

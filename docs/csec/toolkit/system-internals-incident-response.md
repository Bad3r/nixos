# Pentesting Toolkit: System Internals & Incident Response

[Back to Pentesting Toolkit](../toolkit.md)

## System Internals & Incident Response

- bottom
  - run..: `btm`
  - Repo.: <https://github.com/ClementTsang/bottom>
  - Docs.: <https://clementtsang.github.io/bottom/>
  - Desc.: Live process and resource viewer (Rust).
- htop
  - run..: `htop`
  - Repo.: <https://github.com/htop-dev/htop>
  - Docs.: <https://htop.dev/>
  - Desc.: Interactive process and resource viewer.
- bubblewrap
  - run..: `bwrap --bind / / --dev /dev --proc /proc $cmd`
  - Repo.: <https://github.com/containers/bubblewrap>
  - Docs.: <https://github.com/containers/bubblewrap#readme>
  - Desc.: Unprivileged sandboxing primitive used for analysis isolation.
- dmidecode
  - run..: `dmidecode`
  - Repo.: <https://git.savannah.nongnu.org/cgit/dmidecode.git>
  - Docs.: <https://www.nongnu.org/dmidecode/>
  - Desc.: SMBIOS hardware and firmware inventory.
- iotop
  - run..: `iotop`
  - Repo.: <https://repo.or.cz/w/iotop.git>
  - Docs.: <http://guichaz.free.fr/iotop/>
  - Desc.: Per-process IO accounting for live triage.
- lsof
  - run..: `lsof -p $pid`
  - Repo.: <https://github.com/lsof-org/lsof>
  - Docs.: <https://github.com/lsof-org/lsof#readme>
  - Desc.: Lists open files, sockets, and locks for incident triage.
- procps
  - run..: `ps auxf`
  - Repo.: <https://gitlab.com/procps-ng/procps>
  - Docs.: <https://gitlab.com/procps-ng/procps#readme>
  - Desc.: ps, top, free, and friends for process inspection.
- psmisc
  - run..: `pstree -p`
  - Repo.: <https://gitlab.com/psmisc/psmisc>
  - Docs.: <https://gitlab.com/psmisc/psmisc#readme>
  - Desc.: killall, pstree, and fuser.
- sysstat
  - run..: `sar -A`
  - Repo.: <https://github.com/sysstat/sysstat>
  - Docs.: <https://sysstat.github.io/>
  - Desc.: Historical CPU, IO, and network statistics (sar).
- usbutils
  - run..: `lsusb -v`
  - Repo.: <https://github.com/gregkh/usbutils>
  - Docs.: <https://github.com/gregkh/usbutils#readme>
  - Desc.: lsusb and friends for USB device inspection.

# Songbird troubleshooting: storage

- [songbird-troubleshooting.md](songbird-troubleshooting.md)

## XFS reports metadata corruption on /data

A metadata block written while memory was unstable fails the XFS verifier on every read, and each nightly `updatedb` walk logs it again.

```sh
journalctl _TRANSPORT=kernel -g 'Metadata corruption'
sudo xfs_scrub -n -v /data
```

Settle the DRAM speed first, as [songbird-hardware.md](songbird-hardware.md) describes, because a repair on unstable memory writes new damage.
Then unmount `/data` as the last section describes and repair it offline.

```sh
sudo xfs_repair -n /dev/mapper/data
sudo xfs_repair /dev/mapper/data
sudo mount /data
sudo xfs_scrub -n /data
```

When `xfs_repair` reports a dirty log, mount and unmount `/data` once to replay it, since `-L` discards the log instead.
`Info:` lines about lookalike names such as `el` and `e1` flag file names, not damage.

## xfs_scrub hangs in phase 4 and /data stops responding

Online repair of a damaged inode oopses the kernel in `xrep_dinode_count_rtgroup_rmaps`, and the dead thread keeps an allocation group header locked.

```sh
sudo dmesg | grep -B2 -A2 'RIP:.*xfs_btree_query_all'
```

The remaining `xfs_scrub` threads sit in `D` state and ignore every signal, so reboot, then repair offline as the previous section describes.
Run `xfs_scrub` with `-n` only on this host.

## /data refuses to unmount

The R2 FUSE mounts under `/data/r2/mount`, the R2 bisync timers, and qBittorrent keep `/data` busy.
`systemctl stop data.mount` then either fails with `target is busy` or hangs.

```sh
findmnt -R /data
sudo fuser -vm /data
```

Stop the holders, then unmount with `umount`.

```sh
sudo systemctl stop r2-bisync-{docs,fonts,workspace}.{timer,service} r2-mount-{docs,fonts,workspace}.service
sudo systemctl stop qbittorrent-port-forward.service qbittorrent.service qbittorrent-webui.socket
sudo umount /data
```

Mount it back by mount point, because `mount /dev/mapper/data /data` skips the `noatime` option from its fstab entry, then start the holders again.

```sh
sudo mount /data
sudo systemctl start r2-mount-{docs,fonts,workspace}.service r2-bisync-{docs,fonts,workspace}.timer
sudo systemctl start qbittorrent.service qbittorrent-port-forward.service qbittorrent-webui.socket
```

`findmnt -no OPTIONS /data` lists `noatime` once the mount is back.

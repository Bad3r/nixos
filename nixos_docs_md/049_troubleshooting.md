## Troubleshooting

Even after enabling udisks2, volume management might not work. Thunar and/or the desktop takes time to show up. Thunar will spit out this kind of message on start (look at `journalctl --user -b`).

```programlisting
Thunar:2410): GVFS-RemoteVolumeMonitor-WARNING **: remote volume monitor with dbus name org.gtk.Private.UDisks2VolumeMonitor is not supported
```

This is caused by some needed GNOME services not running. This is all fixed by enabling “Launch GNOME services on startup” in the Advanced tab of the Session and Startup settings panel. Alternatively, you can run this command to do the same thing.

```programlisting
$ xfconf-query -c xfce4-session -p /compat/LaunchGNOME -s true
```

It is necessary to log out and log in again for this to take effect.

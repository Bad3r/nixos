## Automatic Upgrades

You can keep a NixOS system up-to-date automatically by adding the following to `configuration.nix`:

```programlisting
{
  system.autoUpgrade.enable = true;
  system.autoUpgrade.allowReboot = true;
}
```

This enables a periodically executed systemd service named `nixos-upgrade.service`. If the `allowReboot` option is `false`, it runs `nixos-rebuild switch --upgrade` to upgrade NixOS to the latest version in the current channel. (To see when the service runs, see `systemctl list-timers`.) If `allowReboot` is `true`, then the system will automatically reboot if the new generation contains a different kernel, initrd or kernel modules. You can also specify a channel explicitly, e.g.

```programlisting
{ system.autoUpgrade.channel = "https://channels.nixos.org/nixos-25.05"; }
```

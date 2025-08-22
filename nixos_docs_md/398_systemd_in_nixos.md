## systemd in NixOS

Packages in Nixpkgs sometimes provide systemd units with them, usually in e.g `#pkg-out#/lib/systemd/`. Putting such a package in `environment.systemPackages` doesn’t make the service available to users or the system.

In order to enable a systemd _system_ service with provided upstream package, use (e.g):

```programlisting
{ systemd.packages = [ pkgs.packagekit ]; }
```

Usually NixOS modules written by the community do the above, plus take care of other details. If a module was written for a service you are interested in, you’d probably need only to use `services.#name#.enable = true;`. These services are defined in Nixpkgs’ [`nixos/modules/` directory](https://github.com/NixOS/nixpkgs/tree/master/nixos/modules) . In case the service is simple enough, the above method should work, and start the service on boot.

_User_ systemd services on the other hand, should be treated differently. Given a package that has a systemd unit file at `#pkg-out#/lib/systemd/user/`, using [`systemd.packages`](options.html#opt-systemd.packages) will make you able to start the service via `systemctl --user start`, but it won’t start automatically on login. However, You can imperatively enable it by adding the package’s attribute to [`systemd.packages`](options.html#opt-systemd.packages) and then do this (e.g):

```programlisting
$ mkdir -p ~/.config/systemd/user/default.target.wants
$ ln -s /run/current-system/sw/lib/systemd/user/syncthing.service ~/.config/systemd/user/default.target.wants/
$ systemctl --user daemon-reload
$ systemctl --user enable syncthing.service
```

If you are interested in a timer file, use `timers.target.wants` instead of `default.target.wants` in the 1st and 2nd command.

Using `systemctl --user enable syncthing.service` instead of the above, will work, but it’ll use the absolute path of `syncthing.service` for the symlink, and this path is in `/nix/store/.../lib/systemd/user/`. Hence [garbage collection](#sec-nix-gc "Cleaning the Nix Store") will remove that file and you will wind up with a broken symlink in your systemd configuration, which in turn will not make the service / timer start on login.

### Defining custom services

You can define services by adding them to `systemd.services`:

```programlisting
{
  systemd.services.myservice = {
    after = [ "network-online.target" ];
    requires = [ "network-online.target" ];

    before = [ "multi-user.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      ExecStart = "...";
    };
  };
}
```

If you want to specify a multi-line script for `ExecStart`, you may want to use `pkgs.writeShellScript`.

### Template units

systemd supports templated units where a base unit can be started multiple times with a different parameter. The syntax to accomplish this is `service-name@instance-name.service`. Units get the instance name passed to them (see `systemd.unit(5)`). NixOS has support for these kinds of units and for template-specific overrides. A service needs to be defined twice, once for the base unit and once for the instance. All instances must include `overrideStrategy = "asDropin"` for the change detection to work. This example illustrates this:

```programlisting
{
  systemd.services = {
    "base-unit@".serviceConfig = {
      ExecStart = "...";
      User = "...";
    };
    "base-unit@instance-a" = {
      overrideStrategy = "asDropin"; # needed for templates to work

      wantedBy = [ "multi-user.target" ]; # causes NixOS to manage the instance

    };
    "base-unit@instance-b" = {
      overrideStrategy = "asDropin"; # needed for templates to work

      wantedBy = [ "multi-user.target" ]; # causes NixOS to manage the instance

      serviceConfig.User = "root"; # also override something for this specific instance

    };
  };
}
```

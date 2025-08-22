## NixOS Configuration File

The NixOS configuration file generally looks like this:

```programlisting
{ config, pkgs, ... }:

{
  # option definitions

}
```

The first line (`{ config, pkgs, ... }:`) denotes that this is actually a function that takes at least the two arguments `config` and `pkgs`. (These are explained later, in chapter [_Writing NixOS Modules_](#sec-writing-modules "Writing NixOS Modules")) The function returns a _set_ of option definitions (`{ ... }`). These definitions have the form `name = value`, where `name` is the name of an option and `value` is its value. For example,

```programlisting
{ config, pkgs, ... }:

{
  services.httpd.enable = true;
  services.httpd.adminAddr = "alice@example.org";
  services.httpd.virtualHosts.localhost.documentRoot = "/webroot";
}
```

defines a configuration with three option definitions that together enable the Apache HTTP Server with `/webroot` as the document root.

Sets can be nested, and in fact dots in option names are shorthand for defining a set containing another set. For instance, [`services.httpd.enable`](options.html#opt-services.httpd.enable) defines a set named `services` that contains a set named `httpd`, which in turn contains an option definition named `enable` with value `true`. This means that the example above can also be written as:

```programlisting
{ config, pkgs, ... }:

{
  services = {
    httpd = {
      enable = true;
      adminAddr = "alice@example.org";
      virtualHosts = {
        localhost = {
          documentRoot = "/webroot";
        };
      };
    };
  };
}
```

which may be more convenient if you have lots of option definitions that share the same prefix (such as `services.httpd`).

NixOS checks your option definitions for correctness. For instance, if you try to define an option that doesn’t exist (that is, doesn’t have a corresponding _option declaration_), `nixos-rebuild` will give an error like:

```programlisting
The option `services.httpd.enable' defined in `/etc/nixos/configuration.nix' does not exist.
```

Likewise, values in option definitions must have a correct type. For instance, `services.httpd.enable` must be a Boolean (`true` or `false`). Trying to give it a value of another type, such as a string, will cause an error:

```programlisting
The option value `services.httpd.enable' in `/etc/nixos/configuration.nix' is not a boolean.
```

Options have various types of values. The most important are:

Strings  
Strings are enclosed in double quotes, e.g.

```programlisting
{
  networking.hostName = "dexter";
}
```

Special characters can be escaped by prefixing them with a backslash (e.g. `\"`).

Multi-line strings can be enclosed in _double single quotes_, e.g.

```programlisting
{
  networking.extraHosts =
    ''
      127.0.0.2 other-localhost
      10.0.0.1 server
    '';
}
```

The main difference is that it strips from each line a number of spaces equal to the minimal indentation of the string as a whole (disregarding the indentation of empty lines), and that characters like `"` and `\` are not special (making it more convenient for including things like shell code). See more info about this in the Nix manual [here](https://nixos.org/nix/manual/#ssec-values).

Booleans  
These can be `true` or `false`, e.g.

```programlisting
{
  networking.firewall.enable = true;
  networking.firewall.allowPing = false;
}
```

Integers  
For example,

```programlisting
{
  boot.kernel.sysctl."net.ipv4.tcp_keepalive_time" = 60;
}
```

(Note that here the attribute name `net.ipv4.tcp_keepalive_time` is enclosed in quotes to prevent it from being interpreted as a set named `net` containing a set named `ipv4`, and so on. This is because it’s not a NixOS option but the literal name of a Linux kernel setting.)

Sets  
Sets were introduced above. They are name/value pairs enclosed in braces, as in the option definition

```programlisting
{
  fileSystems."/boot" =
    { device = "/dev/sda1";
      fsType = "ext4";
      options = [ "rw" "data=ordered" "relatime" ];
    };
}
```

Lists  
The important thing to note about lists is that list elements are separated by whitespace, like this:

```programlisting
{
  boot.kernelModules = [ "fuse" "kvm-intel" "coretemp" ];
}
```

List elements can be any other type, e.g. sets:

```programlisting
{
  swapDevices = [ { device = "/dev/disk/by-label/swap"; } ];
}
```

Packages  
Usually, the packages you need are already part of the Nix Packages collection, which is a set that can be accessed through the function argument `pkgs`. Typical uses:

```programlisting
{
  environment.systemPackages =
    [ pkgs.thunderbird
      pkgs.emacs
    ];

  services.postgresql.package = pkgs.postgresql_14;
}
```

The latter option definition changes the default PostgreSQL package used by NixOS’s PostgreSQL service to 14.x. For more information on packages, including how to add new ones, see [the section called “Adding Custom Packages”](#sec-custom-packages "Adding Custom Packages").

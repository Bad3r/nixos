## Systemd-specific Service Options

[`_module.args`](#systemd-service-opt-_module.args)  
Additional arguments passed to each module in addition to ones like `lib`, `config`, and `pkgs`, `modulesPath`.

This option is also available to all submodules. Submodules do not inherit args from their parent module, nor do they provide args to their parent module or sibling submodules. The sole exception to this is the argument `name` which is provided by parent modules to a submodule and contains the attribute name the submodule is bound to, or a unique generated name if it is not bound to an attribute.

Some arguments are already passed by default, of which the following _cannot_ be changed with this option:

- `lib`: The nixpkgs library.

- `config`: The results of all options after merging the values from all modules together.

- `options`: The options declared in all modules.

- `specialArgs`: The `specialArgs` argument passed to `evalModules`.

- All attributes of `specialArgs`

  Whereas option values can generally depend on other option values thanks to laziness, this does not apply to `imports`, which must be computed statically before anything else.

  For this reason, callers of the module system can provide `specialArgs` which are available during import resolution.

  For NixOS, `specialArgs` includes `modulesPath`, which allows you to import extra modules from the nixpkgs package tree without having to somehow make the module aware of the location of the `nixpkgs` or NixOS directories.

  ```programlisting
  { modulesPath, ... }: {
    imports = [
      (modulesPath + "/profiles/minimal.nix")
    ];
  }
  ```

For NixOS, the default value for this option includes at least this argument:

- `pkgs`: The nixpkgs package set according to the `nixpkgs.pkgs` option.

_Type:_ lazy attribute set of raw value

_Declared by:_

|                                                                                                          |
| -------------------------------------------------------------------------------------------------------- |
| ` `[`<nixpkgs/lib/modules.nix>`](https://github.com/NixOS/nixpkgs/blob/release-25.11/lib/modules.nix)` ` |

[`process.argv`](#systemd-service-opt-process.argv)  
Command filename and arguments for starting this service. This is a raw command-line that should not contain any shell escaping. If expansion of environmental variables is required then use a shell script or `importas` from `pkgs.execline`.

_Type:_ list of (string or absolute path convertible to it)

_Example:_ `[ (lib.getExe config.package) "--nobackground" ]`

_Declared by:_

|                                                                                                                                                                              |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ` `[`<nixpkgs/nixos/modules/system/service/portable/service.nix>`](https://github.com/NixOS/nixpkgs/blob/release-25.11/nixos/modules/system/service/portable/service.nix)` ` |

[`services`](#systemd-service-opt-services)  
A collection of [modular services](https://nixos.org/manual/nixos/unstable/#modular-services) that are configured in one go.

You could consider the sub-service relationship to be an ownership relation. It **does not** automatically create any other relationship between services (e.g. systemd slices), unless perhaps such a behavior is explicitly defined and enabled in another option.

_Type:_ attribute set of (submodule)

_Default:_ `{ }`

_Declared by:_

|                                                                                                                                                                              |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ` `[`<nixpkgs/nixos/modules/system/service/portable/service.nix>`](https://github.com/NixOS/nixpkgs/blob/release-25.11/nixos/modules/system/service/portable/service.nix)` ` |
| ` `[`<nixpkgs/nixos/modules/system/service/systemd/service.nix>`](https://github.com/NixOS/nixpkgs/blob/release-25.11/nixos/modules/system/service/systemd/service.nix)` `   |

[`systemd.service`](#systemd-service-opt-systemd.service)  
Alias of `systemd.services.""`.

_Type:_ submodule

_Declared by:_

|                                                                                                                                                                            |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ` `[`<nixpkgs/nixos/modules/system/service/systemd/service.nix>`](https://github.com/NixOS/nixpkgs/blob/release-25.11/nixos/modules/system/service/systemd/service.nix)` ` |

[`systemd.services`](#systemd-service-opt-systemd.services)  
This module configures systemd services, with the notable difference that their unit names will be prefixed with the abstract service name.

This option’s value is not suitable for reading, but you can define a module here that interacts with just the unit configuration in the host system configuration.

Note that this option contains _deferred_ modules. This means that the module has not been combined with the system configuration yet, no values can be read from this option. What you can do instead is define a module that reads from the module arguments (such as `config`) that are available when the module is merged into the system configuration.

_Type:_ lazy attribute set of module

_Default:_ `{ }`

_Declared by:_

|                                                                                                                                                                            |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ` `[`<nixpkgs/nixos/modules/system/service/systemd/service.nix>`](https://github.com/NixOS/nixpkgs/blob/release-25.11/nixos/modules/system/service/systemd/service.nix)` ` |

[`systemd.socket`](#systemd-service-opt-systemd.socket)  
Alias of `systemd.sockets.""`.

_Type:_ submodule

_Declared by:_

|                                                                                                                                                                            |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ` `[`<nixpkgs/nixos/modules/system/service/systemd/service.nix>`](https://github.com/NixOS/nixpkgs/blob/release-25.11/nixos/modules/system/service/systemd/service.nix)` ` |

[`systemd.sockets`](#systemd-service-opt-systemd.sockets)  
Declares systemd socket units. Names will be prefixed by the service name / path.

See `systemd.services`.

_Type:_ lazy attribute set of module

_Default:_ `{ }`

_Declared by:_

|                                                                                                                                                                            |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ` `[`<nixpkgs/nixos/modules/system/service/systemd/service.nix>`](https://github.com/NixOS/nixpkgs/blob/release-25.11/nixos/modules/system/service/systemd/service.nix)` ` |

# Contributing to this manual

**Table of Contents**

[Development environment](#sec-contributing-development-env)

[Testing redirects](#sec-contributing-redirects)

[Contributing to the `configuration.nix` options documentation](#sec-contributing-options)

[Contributing to `nixos-*` tools’ manpages](#sec-contributing-nixos-tools)

The sources of the NixOS manual are in the [nixos/doc/manual](https://github.com/NixOS/nixpkgs/tree/master/nixos/doc/manual) subdirectory of the [Nixpkgs](https://github.com/NixOS/nixpkgs) repository. This manual uses the [Nixpkgs manual syntax](https://nixos.org/manual/nixpkgs/unstable/#sec-contributing-markup).

You can quickly check your edits with the following:

```programlisting
$ cd /path/to/nixpkgs
$ $EDITOR doc/nixos/manual/... # edit the manual

$ nix-build nixos/release.nix -A manual.x86_64-linux
```

If the build succeeds, the manual will be in `./result/share/doc/nixos/index.html`.

There’s also [a convenient development daemon](https://nixos.org/manual/nixpkgs/unstable/#sec-contributing-devmode).

The above instructions don’t deal with the appendix of available `configuration.nix` options, and the manual pages related to NixOS. These are built, and written in a different location and in a different format, as explained in the next sections.

# Development environment

In order to reduce repetition, consider using tools from the provided development environment:

Load it from the NixOS documentation directory with

```programlisting
$ cd /path/to/nixpkgs/nixos/doc/manual
$ nix-shell
```

To load the development utilities automatically when entering that directory, [set up `nix-direnv`](https://nix.dev/guides/recipes/direnv).

Make sure that your local files aren’t added to Git history by adding the following lines to `.git/info/exclude` at the root of the Nixpkgs repository:

```programlisting
/**/.envrc
/**/.direnv
```

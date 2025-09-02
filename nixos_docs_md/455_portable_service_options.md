## Portable Service Options

[`_module.args`](#service-opt-_module.args)
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

[`process.argv`](#service-opt-process.argv)
Command filename and arguments for starting this service. This is a raw command-line that should not contain any shell escaping. If expansion of environmental variables is required then use a shell script or `importas` from `pkgs.execline`.

_Type:_ list of (string or absolute path convertible to it)

_Example:_ `[ (lib.getExe config.package) "--nobackground" ]`

_Declared by:_

|                                                                                                                                                                              |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ` `[`<nixpkgs/nixos/modules/system/service/portable/service.nix>`](https://github.com/NixOS/nixpkgs/blob/release-25.11/nixos/modules/system/service/portable/service.nix)` ` |

[`services`](#service-opt-services)
A collection of [modular services](https://nixos.org/manual/nixos/unstable/#modular-services) that are configured in one go.

You could consider the sub-service relationship to be an ownership relation. It **does not** automatically create any other relationship between services (e.g. systemd slices), unless perhaps such a behavior is explicitly defined and enabled in another option.

_Type:_ attribute set of (submodule)

_Default:_ `{ }`

_Declared by:_

|                                                                                                                                                                              |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ` `[`<nixpkgs/nixos/modules/system/service/portable/service.nix>`](https://github.com/NixOS/nixpkgs/blob/release-25.11/nixos/modules/system/service/portable/service.nix)` ` |

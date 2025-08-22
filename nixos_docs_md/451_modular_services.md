## Modular Services

**Table of Contents**

[Portability](#modular-service-portability)

[Composition and Ownership](#modular-service-composition)

[Migration](#modular-service-migration)

[Portable Service Options](#modular-service-options-portable)

[Systemd-specific Service Options](#modular-service-options-systemd)

Status: in development. This functionality is new in NixOS 25.11, and significant changes should be expected. We’d love to hear your feedback in [https://github.com/NixOS/nixpkgs/pull/372170](https://github.com/NixOS/nixpkgs/pull/372170)

Traditionally, NixOS services were defined using sets of options _in_ modules, not _as_ modules. This made them non-modular, resulting in problems with composability, reuse, and portability.

A configuration management framework is an application of `evalModules` with the `class` and `specialArgs` input attribute set to particular values. NixOS is such a configuration management framework, and so are [Home Manager](https://github.com/nix-community/home-manager) and [`nix-darwin`](https://github.com/lnl7/nix-darwin).

The service management component of a configuration management framework is the set of module options that connects Nix expressions with the underlying service (or process) manager. For NixOS this is the module wrapping [`systemd`](https://systemd.io/), on `nix-darwin` this is the module wrapping [`launchd`](https://en.wikipedia.org/wiki/Launchd).

A _modular service_ is a [module](https://nixos.org/manual/nixpkgs/stable/#module-system) that defines values for a core set of options declared in the service management component of a configuration management framework, including which program to run. Since it’s a module, it can be composed with other modules via `imports` to extend its functionality.

NixOS provides two options into which such modules can be plugged:

- `system.services.<name>`

- an option for user services (TBD)

Crucially, these options have the type [`attrsOf`](#sec-option-types-composed "Composed types") [`submodule`](#sec-option-types-submodule "Submodule types"). The name of the service is the attribute name corresponding to `attrsOf`. The `submodule` is pre-loaded with two modules:

- a generic module that is intended to be portable

- a module with systemd-specific options, whose values or defaults derive from the generic module’s option values.

So note that the default value of `system.services.<name>` is not a complete service. It requires that the user provide a value, and this is typically done by importing a module. For example:

```programlisting
{
  system.services.my-service-instance = {
    imports = [ pkgs.some-application.services.some-service-module ];
    foo.settings = {
      # ...

    };
  };
}
```

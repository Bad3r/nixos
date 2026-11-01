# Apps module package sources

The `package` option of an app module names where the program comes from.
Confirm the attribute exists before writing the module.

## nixpkgs

```sh
nix eval nixpkgs#<name>.meta.description --raw
```

When that eval fails with an alias or deprecation error, `nix eval nixpkgs#<name> --raw` shows the actual package name.
The module declares `package = lib.mkPackageOption pkgs "<name>" { };`.

## External flake inputs

A package can come from another flake input instead of nixpkgs, such as `llm-agents.nix`:

```sh
nix eval github:<owner>/<repo>#packages.x86_64-linux --apply builtins.attrNames
nix eval github:<owner>/<repo>#packages.x86_64-linux.<name>.meta.description --raw
nix eval github:<owner>/<repo>#packages.x86_64-linux.<name>.meta.homepage --raw
```

- The outer module signature is `{ inputs, ... }:` instead of `_:`, to reach the flake inputs.

- The package option names the input:

  ```nix
  package = lib.mkOption {
    type = lib.types.package;
    default = inputs.<flake-name>.packages.${pkgs.stdenv.hostPlatform.system}.<package-name>;
    defaultText = lib.literalExpression "inputs.<flake-name>.packages.\${system}.<package-name>";
    description = "The <package-name> package to use.";
  };
  ```

- The header's `Notes:` section names the source flake.

`modules/agents/claude-code/nixos.nix`, `modules/apps/spec-kit/nixos.nix`, and `modules/agents/codex/nixos.nix` are complete examples.

## Python packages

Packages from `python3Packages`, such as `pyyaml`, `cloudflare`, or `yamllint`, are not top-level attributes, so `nixpkgs#<name>` does not find them:

```sh
nix eval nixpkgs#python3Packages.<name>.meta.description --raw
nix eval nixpkgs#python3Packages.<name>.meta.homepage --raw
nix eval nixpkgs#python3Packages.<name>.version --raw
```

- The package option takes the list-path form: `package = lib.mkPackageOption pkgs [ "python3Packages" "<name>" ] { };`.
- Everything else, the outer `_:`, the `let` binding, the options namespace, `lib.mkIf`, and the export, matches a nixpkgs module.
- A library-only package with no CLI documents its key API entry points, functions or classes, under `Options:`.

`modules/apps/pyyaml.nix` (library) and `modules/apps/cloudflare-python-sdk.nix` (SDK with a CLI) are complete examples.

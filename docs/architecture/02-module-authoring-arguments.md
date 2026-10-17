# Custom Module Arguments

NixOS modules can receive a small set of repo-specific arguments as ordinary function parameters.
The shared host helper `modules/configurations/nixos.nix` injects `hostName`, `inputs`, `metaOwner`, and `secretsRoot` into every deferred host module, through both `_module.args` and the wrapping `nixosSystem` `specialArgs`.
New hosts get these arguments without declaring them again.

## NixOS Arguments

Every NixOS module reached through the host closure can take each of these:

- `metaOwner` (attrs): owner identity, `username` and `sshKeys`, from `lib/meta-owner-profile.nix` through `flake.nix` and the shared helper; consumed by Home Manager users and secrets.
- `secretsRoot` (path): the repo `secrets/` directory, the base for `sopsFile` references and `pathExists` guards.
- `inputs` (attrs): the flake inputs, so a module uses `inputs.<flake>.nixosModules` without importing the flake again.
- `hostName` (string): the host attribute name, consumed by `modules/hosts/common/hostname.nix`.

## Home Manager Arguments

Home Manager modules receive `inputs`, `metaOwner`, and `secretsRoot` through `home-manager.extraSpecialArgs`, set in `modules/home-manager/nixos.nix`, as in this consumer:

```nix
# modules/home/context7-secrets.nix (excerpt)
{
  flake.homeManagerModules.context7Secrets =
    { lib, config, metaOwner, secretsRoot, ... }:
    let
      cfg = config.home.context7Secrets;
      ctxFile = secretsRoot + "/context7.yaml";
    in
    {
      config = lib.mkIf (cfg.enable && builtins.pathExists ctxFile) {
        sops.secrets."context7/api-key" = {
          sopsFile = ctxFile;
          path = "/home/${metaOwner.username}/.local/share/context7/api-key";
          # ...
        };
      };
    };
}
```

## App Helpers

`config.flake.lib.nixos`, with the `hasApp`, `getApp`, `getApps`, `getAllApps`, and `getAppOr` helpers, is a flake-parts helper, not a NixOS module argument.
Host-side modules read it from the flake-parts outer scope.
The same helpers are published as `_module.args.nixosAppHelpers` at flake-parts scope only, so a NixOS module that declares `{ nixosAppHelpers, ... }:` fails to evaluate.

## The Contract

Custom args are the contract between hosts and downstream modules.
A new shared arg updates both `_module.args` and `specialArgs` in `modules/configurations/nixos.nix`, and a host-specific arg belongs in a host-owned module.
A missing arg surfaces as an evaluation error that names the missing parameter.

/*
  Package: sss-nix-repair
  Description: Guided Nix store repair workflow with generation triage and optional cleanup.
  Homepage: https://github.com/vx/nixos
  Documentation: https://github.com/vx/nixos/tree/main/docs/troubleshooting/nix-store-maintenance.md
  Repository: https://github.com/vx/nixos

  Summary:
    * Runs `nh clean all` and `nix store verify --repair` using host-safe defaults for routine recovery.
    * Maps corrupted store paths to user and system generations, then prompts before deleting non-current affected generations.

  Options:
    --keep-since: Override retention window passed to `nh clean all`.
    --keep: Override generation count kept by `nh clean all`.
    --no-clean: Skip the `nh clean` phase.
    --no-verify: Skip the `nix store verify` phase.
    --trust: Include trust/signature checks during verify.
    --yes: Auto-approve deletion prompts.
    --dry-run: Print mutating commands without executing them.
*/
_:
let
  SssNixRepairModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."sss-nix-repair".extended;
    in
    {
      options.programs."sss-nix-repair".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable sss-nix-repair.";
        };

        package = lib.mkPackageOption pkgs "sss-nix-repair" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."sss-nix-repair" = SssNixRepairModule;
}

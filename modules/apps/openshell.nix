/*
  Package: openshell
  Description: NVIDIA runtime that runs autonomous AI agents in policy-governed sandboxes.
  Homepage: https://docs.nvidia.com/openshell/index.html
  Documentation: https://docs.nvidia.com/openshell/latest/
  Repository: https://github.com/NVIDIA/OpenShell

  Summary:
    * Creates sandboxes for agents and enforces declared file, network, credential, and inference policy.
    * Starts and manages a local gateway on Docker, Podman, or host virtualization.

  Options:
    sandbox: Create, list, connect to, and delete sandboxes.
    policy: Inspect and change a sandbox's policy.
    gateway: Start, stop, and select gateways.
    doctor: Diagnose gateway issues.
    term: Launch the interactive TUI.
*/
_:
let
  OpenshellModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.openshell.extended;
    in
    {
      options.programs.openshell.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable openshell.";
        };

        package = lib.mkPackageOption pkgs "openshell" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.openshell = OpenshellModule;
}

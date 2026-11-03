/*
  Package: openshell
  Description: NVIDIA runtime that runs autonomous AI agents in policy-governed sandboxes.
  Homepage: https://docs.nvidia.com/openshell/index.html
  Documentation: https://docs.nvidia.com/openshell/latest/
  Repository: https://github.com/NVIDIA/OpenShell

  Summary:
    * Creates sandboxes for agents and enforces declared file, network, credential, and inference policy.
    * Runs a local gateway as the `openshell-gateway` user service on rootless Podman, with mTLS on 127.0.0.1:17670.
    * Both binaries are built without upstream's anonymous telemetry.

  Options:
    gateway add --local https://127.0.0.1:17670: Register the local gateway once; picks up its mTLS client bundle.
    sandbox: Create, list, connect to, and delete sandboxes.
    rule: Review and approve the network rules a sandbox requests.
    doctor check: Validate gateway prerequisites.
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

        gatewayPackage = lib.mkPackageOption pkgs "openshell-gateway" { };
      };

      config = lib.mkIf cfg.enable {
        # the gateway runs sandboxes on the rootless Podman socket
        programs.podman.extended.enable = lib.mkOverride 1050 true;

        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.openshell = OpenshellModule;
}

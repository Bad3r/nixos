/*
  Package: openshell
  Description: NVIDIA runtime that runs autonomous AI agents in policy-governed sandboxes.
  Homepage: https://docs.nvidia.com/openshell/index.html
  Documentation: https://docs.nvidia.com/openshell/latest/
  Repository: https://github.com/NVIDIA/OpenShell

  Summary:
    * Creates sandboxes for agents and enforces declared file, network, credential, and inference policy.
    * Runs a gateway as the `openshell-gateway` user service on rootless Podman, with mTLS on every address.
    * Mesh peers reach it through the firewall; workload VMs through `workloads grant`.
    * Both binaries are built without upstream's anonymous telemetry.

  Options:
    gateway add --local https://127.0.0.1:17670: Register the local gateway once; picks up its mTLS client bundle.
    Remote clients: docs/apps/openshell/README.md.
    sandbox: Create, list, connect to, and delete sandboxes.
    rule: Review and approve the network rules a sandbox requests.
    doctor check: Validate gateway prerequisites.
    term: Launch the interactive TUI.
*/
{ config, ... }:
let
  meshInterface = config.flake.lib.nixos._firewallMeshInterface;

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

        gatewayPort = lib.mkOption {
          type = lib.types.port;
          default = 17670;
          description = "Port the gateway serves local, Mesh, and workload clients on.";
        };
      };

      config = lib.mkIf cfg.enable {
        # the gateway runs sandboxes on the rootless Podman socket
        programs.podman.extended.enable = lib.mkOverride 1050 true;

        environment.systemPackages = [ cfg.package ];

        # mTLS admits only holders of the client bundle
        networking.firewall.interfaces.${meshInterface}.allowedTCPPorts = [ cfg.gatewayPort ];
      };
    };
in
{
  flake.nixosModules.apps.openshell = OpenshellModule;
}

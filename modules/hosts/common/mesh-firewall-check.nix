# Approval gate for the CloudflareWARP rule in modules/hosts/common/firewall.nix
# on every shareCommon host: TCP 22 and the host's approved Mesh ranges while
# the WARP app is on, no rule while it is off. The interface is the approved
# scope, so every device enrolled in the team reaches these ports.
# The approved rule, ranges included, is written out rather than read from the
# template or the registry, so a widened firewallLocalTcpPortRanges entry, an
# added port or protocol, or a dropped app gate fails here until approved below.
{ config, lib, ... }:
let
  hosts = config.flake.lib.nixos.hosts;
  formatCaseFailures =
    config.flake.lib.nixos._formatCheckFailures
      or (throw "modules/lib/check-failures.nix no longer exports flake.lib.nixos._formatCheckFailures");
  meshInterface =
    config.flake.lib.nixos._firewallMeshInterface
      or (throw "modules/hosts/common/firewall.nix no longer exports flake.lib.nixos._firewallMeshInterface");
  approvedMeshRanges = {
    songbird = [
      {
        from = 8000;
        to = 8999;
      }
    ];
    tpnix = [
      {
        from = 8000;
        to = 9999;
      }
    ];
  };
  noRule = {
    allowedTCPPorts = [ ];
    allowedTCPPortRanges = [ ];
    allowedUDPPorts = [ ];
    allowedUDPPortRanges = [ ];
  };
  sharedHosts = lib.filterAttrs (
    name: _: hosts.${name}.shareCommon or false
  ) config.flake.nixosConfigurations;
  # Every real shareCommon host enables cloudflare-warp, so the false arm
  # below and firewall.nix's warpEnabled gate have no host proving them
  # without a forced-off variant of each.
  warpOffHosts = lib.mapAttrs' (
    name: nixos:
    lib.nameValuePair "${name} (cloudflare-warp off)" (
      nixos.extendModules {
        modules = [ { programs.cloudflare-warp.extended.enable = lib.mkForce false; } ];
      }
    )
  ) sharedHosts;
  failuresOf =
    hostName: nixos:
    let
      ruleSet = lib.getAttrs (lib.attrNames noRule) (
        nixos.config.networking.firewall.interfaces.${meshInterface} or noRule
      );
      approved =
        if nixos.config.programs.cloudflare-warp.extended.enable then
          noRule
          // {
            allowedTCPPorts = [ 22 ];
            allowedTCPPortRanges = approvedMeshRanges.${hostName} or [ ];
          }
        else
          noRule;
    in
    lib.optional (ruleSet != approved)
      "${hostName}: ${meshInterface} opens ${builtins.toJSON ruleSet}, approved ${builtins.toJSON approved} (approvedMeshRanges in modules/hosts/common/mesh-firewall-check.nix)";
  failures = lib.concatLists (lib.mapAttrsToList failuresOf (sharedHosts // warpOffHosts));
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.hosts-common-mesh-firewall =
        if sharedHosts == { } then
          throw "hosts-common-mesh-firewall: no shareCommon host is configured, so the check would pass vacuously"
        else if failures != [ ] then
          throw (formatCaseFailures "hosts-common-mesh-firewall" failures)
        else
          pkgs.runCommandLocal "hosts-common-mesh-firewall-ok" { } "touch $out";
    };
}

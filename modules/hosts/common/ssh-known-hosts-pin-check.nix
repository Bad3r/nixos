# Approval gate for the Mesh-address pin modules/hosts/common/ssh-known-hosts.nix
# renders into programs.ssh.knownHosts: every host with a fleetHostKeys entry
# must carry each recorded peer meshIp in that peer's fleet-<peer> hostNames,
# or ssh <peer>.warp (modules/networking/ssh-hosts.nix) is trust-on-first-use
# against an address the whole Zero Trust team shares.
{ config, lib, ... }:
let
  fleetHostKeys = config.flake.lib.nixos.fleetHostKeys;
  meshIpOf = config.flake.lib.nixos.meshIpOf;
  formatCaseFailures =
    config.flake.lib.nixos._formatCheckFailures
      or (throw "modules/lib/check-failures.nix no longer exports flake.lib.nixos._formatCheckFailures");
  pinnedHosts = lib.filterAttrs (name: _: fleetHostKeys ? ${name}) config.flake.nixosConfigurations;
  comparisonsOf =
    hostName: nixos:
    lib.concatLists (
      lib.mapAttrsToList (
        peer: _:
        let
          meshIp = meshIpOf peer;
        in
        lib.optional (meshIp != null && peer != hostName) {
          inherit hostName peer meshIp;
          pinned = nixos.config.programs.ssh.knownHosts."fleet-${peer}".hostNames or [ ];
        }
      ) fleetHostKeys
    );
  comparisons = lib.concatLists (lib.mapAttrsToList comparisonsOf pinnedHosts);
  failures = map (
    c:
    "${c.hostName}: fleet-${c.peer} pins ${builtins.toJSON c.pinned}, missing the Mesh address ${c.meshIp}"
  ) (lib.filter (c: !(lib.elem c.meshIp c.pinned)) comparisons);
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.hosts-common-mesh-known-hosts =
        if pinnedHosts == { } then
          throw "hosts-common-mesh-known-hosts: no host has a fleetHostKeys entry, so the check would pass vacuously"
        else if comparisons == [ ] then
          throw "hosts-common-mesh-known-hosts: no pinned host has a peer that records a meshIp, so the check would compare nothing"
        else if failures != [ ] then
          throw (formatCaseFailures "hosts-common-mesh-known-hosts" failures)
        else
          pkgs.runCommandLocal "hosts-common-mesh-known-hosts-ok" { } "touch $out";
    };
}

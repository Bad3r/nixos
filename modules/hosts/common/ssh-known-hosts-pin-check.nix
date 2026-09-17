# Approval gate for the Mesh-name pin modules/hosts/common/ssh-known-hosts.nix
# renders into programs.ssh.knownHosts. Every fleet host must pin each peer's
# <peer>.internal alias before modules/networking/ssh-hosts.nix exposes it.
{ config, lib, ... }:
let
  fleetHostKeys = config.flake.lib.nixos.fleetHostKeys;
  formatCaseFailures =
    config.flake.lib.nixos._formatCheckFailures
      or (throw "modules/lib/check-failures.nix no longer exports flake.lib.nixos._formatCheckFailures");
  pinnedHosts = lib.filterAttrs (name: _: fleetHostKeys ? ${name}) config.flake.nixosConfigurations;
  comparisonsOf =
    hostName: nixos:
    lib.concatLists (
      lib.mapAttrsToList (
        peer: _:
        lib.optional (peer != hostName) {
          inherit hostName peer;
          expected = "${peer}.internal";
          pinned = nixos.config.programs.ssh.knownHosts."fleet-${peer}".hostNames or [ ];
        }
      ) fleetHostKeys
    );
  comparisons = lib.concatLists (lib.mapAttrsToList comparisonsOf pinnedHosts);
  failures = map (
    c: "${c.hostName}: fleet-${c.peer} pins ${builtins.toJSON c.pinned}, missing ${c.expected}"
  ) (lib.filter (c: !(lib.elem c.expected c.pinned)) comparisons);
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.hosts-common-mesh-known-hosts =
        if pinnedHosts == { } then
          throw "hosts-common-mesh-known-hosts: no host has a fleetHostKeys entry, so the check would pass vacuously"
        else if comparisons == [ ] then
          throw "hosts-common-mesh-known-hosts: no pinned host has a fleet peer, so the check would compare nothing"
        else if failures != [ ] then
          throw (formatCaseFailures "hosts-common-mesh-known-hosts" failures)
        else
          pkgs.runCommandLocal "hosts-common-mesh-known-hosts-ok" { } "touch $out";
    };
}

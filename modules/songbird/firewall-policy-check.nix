# Compare the complete evaluated developer-port command lists rather than the
# registry key: a shared CIDR expansion must not broaden Songbird without an
# explicit policy change.
{ config, lib, ... }:
let
  firewall = config.flake.nixosConfigurations.songbird.config.networking.firewall;
  developerPortRange = "8000:8999";
  localNetworkCidrs = [
    "10.0.0.0/8"
    "192.168.0.0/16"
  ];
  startRules = map (
    cidr: "iptables -A nixos-fw -s ${cidr} -p tcp --dport ${developerPortRange} -j nixos-fw-accept"
  ) localNetworkCidrs;
  stopRules = map (
    cidr:
    "iptables -D nixos-fw -s ${cidr} -p tcp --dport ${developerPortRange} -j nixos-fw-accept || true"
  ) localNetworkCidrs;
  developerRuleNeedle = "--dport ${developerPortRange} -j nixos-fw-accept";
  developerStartRules = lib.filter (line: lib.hasInfix developerRuleNeedle line) (
    lib.splitString "\n" firewall.extraCommands
  );
  developerStopRules = lib.filter (line: lib.hasInfix developerRuleNeedle line) (
    lib.splitString "\n" firewall.extraStopCommands
  );
  globalDeveloperRange = lib.any (
    range: range.from <= 8999 && range.to >= 8000
  ) firewall.allowedTCPPortRanges;
  sortRules = rules: lib.sort builtins.lessThan rules;
  startRulesMatch = sortRules developerStartRules == sortRules startRules;
  stopRulesMatch = sortRules developerStopRules == sortRules stopRules;
  failures =
    lib.optional globalDeveloperRange "TCP 8000-8999 is globally published by allowedTCPPortRanges"
    ++ lib.optional (!lib.elem 9999 firewall.allowedTCPPorts) "TCP 9999 is no longer globally open"
    ++ lib.optional (!startRulesMatch) "source-scoped start rules differ from the approved exact list"
    ++ lib.optional (!stopRulesMatch) "source-scoped stop rules differ from the approved exact list";
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.songbird-firewall-port-policy =
        if failures != [ ] then
          throw ("songbird-firewall-port-policy: " + lib.concatStringsSep "; " failures)
        else
          pkgs.runCommandLocal "songbird-firewall-port-policy-ok" { } "touch $out";
    };
}

# Compare the evaluated developer-port rules rather than the registry key: a
# shared CIDR expansion must not broaden Songbird without an explicit policy change.
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
  missingStartRules = lib.subtractLists developerStartRules startRules;
  unexpectedStartRules = lib.subtractLists startRules developerStartRules;
  missingStopRules = lib.subtractLists developerStopRules stopRules;
  unexpectedStopRules = lib.subtractLists stopRules developerStopRules;
  failures =
    lib.optional globalDeveloperRange "TCP 8000-8999 is globally published by allowedTCPPortRanges"
    ++ lib.optional (!lib.elem 9999 firewall.allowedTCPPorts) "TCP 9999 is no longer globally open"
    ++ map (rule: "missing source-scoped start rule: ${rule}") missingStartRules
    ++ map (rule: "unexpected source-scoped start rule: ${rule}") unexpectedStartRules
    ++ map (rule: "missing source-scoped stop rule: ${rule}") missingStopRules
    ++ map (rule: "unexpected source-scoped stop rule: ${rule}") unexpectedStopRules;
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

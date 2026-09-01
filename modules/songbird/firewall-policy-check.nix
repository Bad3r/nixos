# Compare exact evaluated developer-port command lists and reject unscoped
# NixOS allowlists: a shared CIDR expansion must not broaden Songbird without
# an explicit policy change.
{ config, lib, ... }:
let
  firewall = config.flake.nixosConfigurations.songbird.config.networking.firewall;
  # modules/hosts/common/firewall.nix generates one rule per range per CIDR from
  # modules/songbird/policy.nix, so every range is walked here too: a literal or
  # a lib.head would leave a second range generating rules this check never
  # inspects, and it would pass without proving anything about them.
  developerRanges = config.flake.lib.nixos.hosts.songbird.firewallLocalTcpPortRanges;
  portRangeOf = range: "${toString range.from}:${toString range.to}";
  developerPortRanges = map portRangeOf developerRanges;
  localNetworkCidrs =
    config.flake.lib.nixos._firewallLocalNetworkCidrs
      or (throw "modules/hosts/common/firewall.nix no longer exports flake.lib.nixos._firewallLocalNetworkCidrs");
  rulesFor = template: lib.concatMap (range: map (template range) localNetworkCidrs) developerRanges;
  startRules = rulesFor (
    range: cidr:
    "iptables -A nixos-fw -s ${cidr} -p tcp --dport ${portRangeOf range} -j nixos-fw-accept"
  );
  stopRules = rulesFor (
    range: cidr:
    "iptables -D nixos-fw -s ${cidr} -p tcp --dport ${portRangeOf range} -j nixos-fw-accept || true"
  );
  isDeveloperRule =
    line: lib.any (portRange: lib.hasInfix "--dport ${portRange}" line) developerPortRanges;
  developerStartRules = lib.filter isDeveloperRule (lib.splitString "\n" firewall.extraCommands);
  developerStopRules = lib.filter isDeveloperRule (lib.splitString "\n" firewall.extraStopCommands);
  developerPortRangeOverlaps =
    range: lib.any (dev: range.from <= dev.to && range.to >= dev.from) developerRanges;
  developerPortIsUnscoped = port: lib.any (dev: port >= dev.from && port <= dev.to) developerRanges;
  ruleSetPublishesDeveloperPort =
    ruleSet:
    lib.any developerPortRangeOverlaps ruleSet.allowedTCPPortRanges
    || lib.any developerPortIsUnscoped ruleSet.allowedTCPPorts;
  unscopedDeveloperPort =
    ruleSetPublishesDeveloperPort firewall
    || lib.any ruleSetPublishesDeveloperPort (lib.attrValues firewall.interfaces);
  # These probe the predicate's boundary handling, not the policy numbers, so
  # they are anchored to the declared range: literal bounds would fail the
  # moment the policy range legitimately moved.
  firstRange = lib.head developerRanges;
  highestPort = lib.foldl' (acc: range: if range.to > acc then range.to else acc) 0 developerRanges;
  unscopedAllowlistTestCases = lib.optionals (developerRanges != [ ]) [
    {
      name = "global TCP port";
      ruleSet = {
        allowedTCPPortRanges = [ ];
        allowedTCPPorts = [ firstRange.from ];
      };
      expected = true;
    }
    {
      name = "interface TCP range";
      ruleSet = {
        allowedTCPPortRanges = [
          {
            from = firstRange.to;
            to = firstRange.to + 1;
          }
        ];
        allowedTCPPorts = [ ];
      };
      expected = true;
    }
    {
      name = "port past every range";
      ruleSet = {
        allowedTCPPortRanges = [ ];
        allowedTCPPorts = [ (highestPort + 1) ];
      };
      expected = false;
    }
  ];
  unscopedAllowlistFailures = lib.filter (
    test: ruleSetPublishesDeveloperPort test.ruleSet != test.expected
  ) unscopedAllowlistTestCases;
  sortRules = rules: lib.sort builtins.lessThan rules;
  startRulesMatch = sortRules developerStartRules == sortRules startRules;
  stopRulesMatch = sortRules developerStopRules == sortRules stopRules;
  failures =
    lib.optional (
      developerRanges == [ ]
    ) "songbird declares no firewallLocalTcpPortRanges; the source-scoped developer range was removed"
    ++ lib.optional unscopedDeveloperPort "TCP ${lib.concatStringsSep ", " developerPortRanges} is published without the approved source CIDRs"
    ++ lib.optional (!lib.elem 9999 firewall.allowedTCPPorts) "TCP 9999 is no longer globally open"
    ++ lib.optional (!startRulesMatch) "source-scoped start rules differ from the approved exact list"
    ++ lib.optional (!stopRulesMatch) "source-scoped stop rules differ from the approved exact list"
    ++ map (test: "unscoped allowlist predicate mismatch: ${test.name}") unscopedAllowlistFailures;
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

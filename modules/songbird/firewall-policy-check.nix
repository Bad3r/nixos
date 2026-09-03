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
  formatCaseFailures =
    config.flake.lib.nixos._formatCheckFailures
      or (throw "modules/lib/check-failures.nix no longer exports flake.lib.nixos._formatCheckFailures");
  rulesFor = template: lib.concatMap (range: map (template range) localNetworkCidrs) developerRanges;
  startRules = rulesFor (
    range: cidr:
    "iptables -A nixos-fw -s ${cidr} -p tcp --dport ${portRangeOf range} -j nixos-fw-accept"
  );
  stopRules = rulesFor (
    range: cidr:
    "iptables -D nixos-fw -s ${cidr} -p tcp --dport ${portRangeOf range} -j nixos-fw-accept || true"
  );
  # iptables spells the destination port as --dport or --destination-port and
  # multiport as --dports or --destination-ports, each after blanks or `=`,
  # with a comma list of ports and a:b ranges where an empty bound means 0 or
  # 65535. Selecting a line by the numbers it names instead of one flag
  # spelling puts a sub-range or single port opened under any spelling in
  # front of the exact-list comparison, and a value that is not a port number
  # (a service name, a missing value, anything past 65535) fails outright.
  destinationPortFlags = [
    "--dport"
    "--dports"
    "--destination-port"
    "--destination-ports"
  ];
  destinationPortSpecs =
    line:
    let
      tokens = lib.filter (token: builtins.isString token && token != "") (builtins.split "[ \t]+" line);
      count = lib.length tokens;
      valuesAt =
        index: token:
        let
          parts = lib.splitString "=" token;
        in
        if !(lib.elem (lib.head parts) destinationPortFlags) then
          [ ]
        else if lib.length parts > 1 then
          [ (lib.concatStringsSep "=" (lib.tail parts)) ]
        else
          [ (if index + 1 < count then lib.elemAt tokens (index + 1) else "") ];
    in
    lib.concatMap (lib.splitString ",") (lib.concatLists (lib.imap0 valuesAt tokens));
  # The regex rejects leading zeros and overlong digit strings, both of which
  # make lib.toInt throw; the value check keeps it inside the port range.
  portBoundIsValid =
    bound:
    bound == "" || (builtins.match "0|[1-9][0-9]{0,4}" bound != null && lib.toInt bound <= 65535);
  portSpecIsValid =
    spec:
    let
      bounds = lib.splitString ":" spec;
    in
    spec != "" && lib.length bounds <= 2 && lib.all portBoundIsValid bounds;
  portSpecOverlaps =
    spec:
    let
      bounds = lib.splitString ":" spec;
      boundOr = fallback: bound: if bound == "" then fallback else lib.toInt bound;
    in
    developerPortRangeOverlaps {
      from = boundOr 0 (lib.head bounds);
      to = boundOr 65535 (lib.last bounds);
    };
  startLines = lib.splitString "\n" firewall.extraCommands;
  stopLines = lib.splitString "\n" firewall.extraStopCommands;
  # isDeveloperRule and unresolvedPortSpecsOf would otherwise tokenize each
  # line twice; the `or` branch serves the synthetic fixture lines below.
  specsForLine = lib.genAttrs (lib.unique (startLines ++ stopLines)) destinationPortSpecs;
  specsOf = line: specsForLine.${line} or (destinationPortSpecs line);
  unresolvedPortSpecsOf = line: lib.filter (spec: !portSpecIsValid spec) (specsOf line);
  isDeveloperRule = line: lib.any portSpecOverlaps (lib.filter portSpecIsValid (specsOf line));
  developerStartRules = lib.filter isDeveloperRule startLines;
  developerStopRules = lib.filter isDeveloperRule stopLines;
  unresolvedPortSpecs = lib.concatMap (
    line:
    map (spec: "destination port `${spec}` in `${line}` is not a port number") (
      unresolvedPortSpecsOf line
    )
  ) (startLines ++ stopLines);
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
  rule = portArgs: "iptables -A nixos-fw -p tcp ${portArgs} -j nixos-fw-accept";
  developerRuleTestCases = lib.optionals (developerRanges != [ ]) (
    let
      range = portRangeOf firstRange;
    in
    [
      {
        name = "long flag";
        line = rule "--destination-port ${range}";
        expected = true;
      }
      {
        name = "multiport list";
        line = rule "-m multiport --dports 22,${range}";
        expected = true;
      }
      {
        name = "equals separator";
        line = rule "--dport=${range}";
        expected = true;
      }
      {
        name = "tab separator";
        line = rule "--dport\t${range}";
        expected = true;
      }
      {
        name = "single port inside a range";
        line = rule "--dport ${toString firstRange.from}";
        expected = true;
      }
      {
        name = "open-ended range";
        line = rule "--dport ${toString highestPort}:";
        expected = true;
      }
      {
        name = "port past every range";
        line = rule "--dport ${toString (highestPort + 1)}";
        expected = false;
      }
      {
        name = "source port only";
        line = rule "--sport ${range}";
        expected = false;
      }
    ]
  );
  developerRuleFailures = lib.filter (
    test: isDeveloperRule test.line != test.expected
  ) developerRuleTestCases;
  unresolvedTestCases = [
    {
      name = "service name";
      line = rule "--dport http-alt";
      expected = [ "http-alt" ];
    }
    {
      name = "port past 65535";
      line = rule "--dport 65536";
      expected = [ "65536" ];
    }
    {
      name = "flag without a value";
      line = "iptables -A nixos-fw -p tcp --dport";
      expected = [ "" ];
    }
  ];
  unresolvedFailures = lib.filter (
    test: unresolvedPortSpecsOf test.line != test.expected
  ) unresolvedTestCases;
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
    ++ unresolvedPortSpecs
    ++ map (test: "unscoped allowlist predicate mismatch: ${test.name}") unscopedAllowlistFailures
    ++ map (test: "developer rule predicate mismatch: ${test.name}") developerRuleFailures
    ++ map (test: "unresolved port predicate mismatch: ${test.name}") unresolvedFailures;
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.songbird-firewall-port-policy =
        if failures != [ ] then
          throw (formatCaseFailures "songbird-firewall-port-policy" failures)
        else
          pkgs.runCommandLocal "songbird-firewall-port-policy-ok" { } "touch $out";
    };
}

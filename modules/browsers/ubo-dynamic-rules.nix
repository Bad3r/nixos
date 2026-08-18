/*
  Check: uBlock Origin dynamic-filtering rules.

  The browser profile and this evaluation check import the same private helper
  directly. The check keeps malformed dynamic-filter and hostname-switch
  records from being silently discarded by uBO, pins behavior-critical rows
  after normalized validation, rejects duplicate cells, and keeps every
  supported type/action and hostname-switch name/state live.
*/
{ lib, ... }:
let
  uboDynamicRules = import ./_ubo-dynamic-rules.nix { inherit lib; };
  inherit (uboDynamicRules)
    checkedHostnameSwitches
    checkedMediumModeRules
    hostnameSwitchError
    mediumModeRuleError
    ruleFields
    ublockOriginHostnameSwitches
    ublockOriginMediumModeRules
    ;

  evalRules = ruleSet: builtins.tryEval (builtins.deepSeq (checkedMediumModeRules ruleSet) true);
  evalHostnameSwitches =
    switchSet: builtins.tryEval (builtins.deepSeq (checkedHostnameSwitches switchSet) true);
  normalizedRule = rule: lib.concatStringsSep " " (ruleFields rule);

  validHostnameSwitchCases = [
    {
      name = "canonical hostname switches";
      switches = ublockOriginHostnameSwitches;
    }
    {
      name = "all supported hostname switches";
      switches = [
        "no-strict-blocking: * true"
        "no-popups: * false"
        "no-cosmetic-filtering: * on"
        "no-remote-fonts: * off"
        "no-large-media: * true"
        "no-csp-reports: * false"
        "no-scripting: * true"
      ];
    }
    {
      name = "uBO hostname-switch whitespace normalization";
      switches = [ "\tno-csp-reports:\t*\ttrue" ];
    }
  ];

  invalidHostnameSwitches = [
    {
      rule = "no-large-media * true";
      reason = "unknown switch no-large-media";
    }
    {
      rule = "no-larger-media: * true";
      reason = "unknown switch no-larger-media:";
    }
    {
      rule = "no-csp-reports: Example.COM true";
      reason = "hostname Example.COM is not a valid uBO hostname";
    }
    {
      rule = "no-csp-reports: *";
      reason = "expected 3 whitespace-separated fields";
    }
    {
      rule = "no-csp-reports: * maybe";
      reason = "unknown state maybe";
    }
    {
      rule = "no-csp-reports: * true extra";
      reason = "expected 3 whitespace-separated fields";
    }
    {
      rule = "no-csp-reports: * true\nno-large-media: * false";
      reason = "contains a line break, which uBO reads as two separate switches";
    }
    {
      rule = "no-csp-reports: example.com/path true";
      reason = "hostname example.com/path is not a valid uBO hostname";
    }
  ];

  validCases = [
    {
      name = "canonical seeded rules";
      rules = ublockOriginMediumModeRules;
    }
    {
      name = "generic third-party type";
      rules = [ "* * 3p noop" ];
    }
    {
      name = "all supported request types";
      rules = [
        "* * * noop"
        "* * image noop"
        "* * inline-script noop"
        "* * 1p-script noop"
        "* * 3p-script noop"
        "* * 3p-frame noop"
        "* * 3p noop"
      ];
    }
    {
      name = "all supported actions";
      rules = [
        "* * * block"
        "* * * allow"
        "* * * noop"
      ];
    }
    {
      name = "uBO whitespace normalization";
      rules = [ "  *  challenges.cloudflare.com   *  noop  " ];
    }
    {
      name = "bracketed IPv6 host slots";
      rules = [
        "[2606:4700:4700::1111] * 3p-script noop"
        "* [2606:4700:4700::1111] * noop"
      ];
    }
  ];

  # Pair each rejected rule with its expected validator branch so an earlier
  # failure cannot mask a regression in the branch the fixture targets.
  invalidRules = [
    {
      rule = "* challenges.cloudflare.com 3p-script noop";
      reason = "destination challenges.cloudflare.com is named, which uBO accepts only with type *, not 3p-script";
    }
    {
      rule = "* challenges.cloudflare.com/path * noop";
      reason = "destination challenges.cloudflare.com/path is not a valid uBO hostname";
    }
    {
      rule = "github.com/path * 3p-script noop";
      reason = "source github.com/path is not a valid uBO hostname";
    }
    {
      rule = "https://github.com * 3p-script noop";
      reason = "source https://github.com is not a valid uBO hostname";
    }
    {
      rule = "github,com * 3p-script noop";
      reason = "source github,com is not a valid uBO hostname";
    }
    {
      rule = "no-large-media: * * noop";
      reason = "source no-large-media: is not a valid uBO hostname";
    }
    {
      rule = "github%2ecom * 3p-script noop";
      reason = "source github%2ecom is not a valid uBO hostname";
    }
    {
      rule = "github.com. * 3p-script noop";
      reason = "source github.com. is not a valid uBO hostname";
    }
    {
      rule = "github..com * 3p-script noop";
      reason = "source github..com is not a valid uBO hostname";
    }
    {
      rule = "github-.com * 3p-script noop";
      reason = "source github-.com is not a valid uBO hostname";
    }
    {
      rule = "github.com *\n3p-script noop";
      reason = "contains a line break, which uBO reads as two separate rules";
    }
    {
      rule = "github.com *\r3p-script noop";
      reason = "contains a line break, which uBO reads as two separate rules";
    }
    {
      rule = "Login.Okta.com * 3p-script noop";
      reason = "source Login.Okta.com is not a valid uBO hostname";
    }
    {
      rule = "* * unknown-type noop";
      reason = "unknown type unknown-type";
    }
    {
      rule = "* * * permit";
      reason = "unknown action permit";
    }
    {
      rule = "* * 3p-script";
      reason = "expected 4 space-separated fields";
    }
    {
      rule = "* * 3p-script noop extra";
      reason = "expected 4 space-separated fields";
    }
  ];

  # Pin the rows that establish medium mode and the Turnstile exception.
  requiredSeedRules = [
    "* * 3p-script block"
    "* * 3p-frame block"
    "* challenges.cloudflare.com * noop"
  ];

  failedValidHostnameSwitchCases = lib.filter (
    case: !(evalHostnameSwitches case.switches).success
  ) validHostnameSwitchCases;
  acceptedInvalidHostnameSwitches = lib.filter (
    fixture: (evalHostnameSwitches [ fixture.rule ]).success
  ) invalidHostnameSwitches;
  hostnameSwitchReasonMismatches = lib.filter (
    fixture: hostnameSwitchError fixture.rule != fixture.reason
  ) invalidHostnameSwitches;
  hostnameSwitchReasonMismatchMessage =
    fixture:
    let
      actualReason = hostnameSwitchError fixture.rule;
    in
    "${fixture.rule} (expected ${fixture.reason}, got ${
      if actualReason == null then "no error" else actualReason
    })";
  checkedSeedHostnameSwitches = checkedHostnameSwitches ublockOriginHostnameSwitches;
  requiredSeedHostnameSwitches = [
    "no-csp-reports: * true"
    "no-large-media: behind-the-scene false"
  ];
  missingSeedHostnameSwitches = lib.filter (
    switchLine: !(lib.elem (normalizedRule switchLine) (map normalizedRule checkedSeedHostnameSwitches))
  ) requiredSeedHostnameSwitches;

  failedValidCases = lib.filter (case: !(evalRules case.rules).success) validCases;
  acceptedInvalidRules = lib.filter (fixture: (evalRules [ fixture.rule ]).success) invalidRules;
  invalidRuleReasonMismatches = lib.filter (
    fixture: mediumModeRuleError fixture.rule != fixture.reason
  ) invalidRules;
  invalidRuleReasonMismatchMessage =
    fixture:
    let
      actualReason = mediumModeRuleError fixture.rule;
    in
    "${fixture.rule} (expected ${fixture.reason}, got ${
      if actualReason == null then "no error" else actualReason
    })";
  # Check the list consumed by the browser profile, not only the raw producer,
  # so a validator regression cannot silently erase the guarded payload.
  checkedSeedRules = checkedMediumModeRules ublockOriginMediumModeRules;
  missingSeedRulesIn =
    rules:
    let
      normalizedRules = map normalizedRule rules;
    in
    lib.filter (rule: !(lib.elem (normalizedRule rule) normalizedRules)) requiredSeedRules;
  missingSeedRules = missingSeedRulesIn checkedSeedRules;
  # Build variants from required rows so this fixture is independent of the
  # canonical seed spelling and cannot silently no-op or false-fail.
  whitespaceVariantRequiredRules = map (
    rule: "\t" + lib.replaceStrings [ " " ] [ "  " ] rule
  ) requiredSeedRules;
  normalizedRequiredSeedRules = checkedMediumModeRules whitespaceVariantRequiredRules;
  normalizedRequiredSeedContractWorks =
    whitespaceVariantRequiredRules != requiredSeedRules
    && missingSeedRulesIn normalizedRequiredSeedRules == [ ];
  # uBO's setCell overwrites earlier rows for the same source, destination, and
  # type, so reject duplicate cells in the checked payload.
  ruleCell = rule: lib.concatStringsSep " " (lib.take 3 (ruleFields rule));
  duplicateCellsIn =
    rules:
    let
      cells = map ruleCell rules;
    in
    lib.unique (lib.filter (cell: lib.count (candidate: candidate == cell) cells > 1) cells);
  duplicateCells = duplicateCellsIn checkedSeedRules;
  # Exercise the failure path so weakening the count or key projection cannot
  # leave the seed-only assertion green.
  duplicateDetectorWorks = duplicateCellsIn (checkedSeedRules ++ [ "* * 3p-script noop" ]) != [ ];
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks."browsers/ubo-dynamic-rules" =
        assert lib.assertMsg (
          checkedSeedHostnameSwitches == ublockOriginHostnameSwitches
        ) "browsers/ubo-dynamic-rules: hostname-switch validation no longer returns the seed unchanged";
        assert lib.assertMsg (missingSeedHostnameSwitches == [ ]) (
          "browsers/ubo-dynamic-rules: hostname-switch seed is missing required rows: "
          + lib.concatStringsSep "; " missingSeedHostnameSwitches
        );
        assert lib.assertMsg (failedValidHostnameSwitchCases == [ ]) (
          "browsers/ubo-dynamic-rules: valid hostname-switch fixtures failed: "
          + lib.concatStringsSep ", " (map (case: case.name) failedValidHostnameSwitchCases)
        );
        assert lib.assertMsg (acceptedInvalidHostnameSwitches == [ ]) (
          "browsers/ubo-dynamic-rules: invalid hostname switches accepted: "
          + lib.concatStringsSep "; " (map (fixture: fixture.rule) acceptedInvalidHostnameSwitches)
        );
        assert lib.assertMsg (hostnameSwitchReasonMismatches == [ ]) (
          "browsers/ubo-dynamic-rules: hostname-switch fixture reasons changed: "
          + lib.concatStringsSep "; " (map hostnameSwitchReasonMismatchMessage hostnameSwitchReasonMismatches)
        );
        assert lib.assertMsg (
          checkedSeedRules == ublockOriginMediumModeRules
        ) "browsers/ubo-dynamic-rules: rule validation no longer returns the seed unchanged";
        assert lib.assertMsg (missingSeedRules == [ ]) (
          "browsers/ubo-dynamic-rules: seed is missing required rules: "
          + lib.concatStringsSep "; " missingSeedRules
        );
        assert lib.assertMsg normalizedRequiredSeedContractWorks
          "browsers/ubo-dynamic-rules: normalized required-row comparison rejected an equivalent rule";
        assert lib.assertMsg (failedValidCases == [ ]) (
          "browsers/ubo-dynamic-rules: valid fixtures failed: "
          + lib.concatStringsSep ", " (map (case: case.name) failedValidCases)
        );
        assert lib.assertMsg (acceptedInvalidRules == [ ]) (
          "browsers/ubo-dynamic-rules: invalid fixtures accepted: "
          + lib.concatStringsSep "; " (map (fixture: fixture.rule) acceptedInvalidRules)
        );
        assert lib.assertMsg (invalidRuleReasonMismatches == [ ]) (
          "browsers/ubo-dynamic-rules: invalid fixture reasons changed: "
          + lib.concatStringsSep "; " (map invalidRuleReasonMismatchMessage invalidRuleReasonMismatches)
        );
        assert lib.assertMsg (duplicateCells == [ ]) (
          "browsers/ubo-dynamic-rules: seed defines the same cell more than once: "
          + lib.concatStringsSep "; " duplicateCells
        );
        assert lib.assertMsg duplicateDetectorWorks
          "browsers/ubo-dynamic-rules: duplicate-cell detection no longer reports a duplicated cell";
        pkgs.runCommand "ubo-dynamic-rules-check" { } "touch $out";
    };
}

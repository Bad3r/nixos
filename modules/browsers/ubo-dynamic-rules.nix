/*
  Check: uBlock Origin dynamic-filtering rules.

  The browser profile imports the private helper directly, while this module
  exports the same validator and rule list through the existing private
  `flake.lib.nixos` namespace. The evaluation check keeps malformed rules from
  being silently discarded by uBO and keeps every supported type/action live.
*/
{ config, lib, ... }:
let
  uboDynamicRules = import ./_ubo-dynamic-rules.nix { inherit lib; };
  exportedRules = config.flake.lib.nixos._uboDynamicRules or null;
  rules =
    if exportedRules == null then
      throw "browsers/ubo-dynamic-rules: private uBO rule helper was not exported"
    else
      exportedRules;
  inherit (rules)
    checkedMediumModeRules
    ublockOriginMediumModeRules
    ;

  evalRules = ruleSet: builtins.tryEval (builtins.deepSeq (checkedMediumModeRules ruleSet) true);

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
  ];

  invalidRules = [
    "* challenges.cloudflare.com 3p-script noop"
    "* challenges.cloudflare.com/path * noop"
    "github.com/path * 3p-script noop"
    "https://github.com * 3p-script noop"
    "github,com * 3p-script noop"
    "no-large-media: * * noop"
    "github%2ecom * 3p-script noop"
    "github.com. * 3p-script noop"
    "Login.Okta.com * 3p-script noop"
    "* * unknown-type noop"
    "* * * permit"
    "* * 3p-script"
    "* * 3p-script noop extra"
  ];

  failedValidCases = lib.filter (case: !(evalRules case.rules).success) validCases;
  acceptedInvalidRules = lib.filter (rule: (evalRules [ rule ]).success) invalidRules;
in
{
  flake.lib.nixos._uboDynamicRules = uboDynamicRules;

  perSystem =
    { pkgs, ... }:
    {
      checks."browsers/ubo-dynamic-rules" =
        assert lib.assertMsg (failedValidCases == [ ]) (
          "browsers/ubo-dynamic-rules: valid fixtures failed: "
          + lib.concatStringsSep ", " (map (case: case.name) failedValidCases)
        );
        assert lib.assertMsg (acceptedInvalidRules == [ ]) (
          "browsers/ubo-dynamic-rules: invalid fixtures accepted: "
          + lib.concatStringsSep "; " acceptedInvalidRules
        );
        pkgs.runCommand "ubo-dynamic-rules-check" { } "touch $out";
    };
}

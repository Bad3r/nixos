# Coverage for the sub-toggle classifier in modules/hosts/common/checks.nix.
#
# The three toggles registered across the fleet are all programs-namespace and
# all diverge from the baseline, so a host closure reaches neither the services
# lookup nor the no-op branch. Resolving only against programs shipped that way:
# a sub-toggle on a services app (espanso, autorandr, flameshot, pcscd,
# protonmail-bridge, thinkfan, usbmuxd) reported as an out-of-sync baseline
# that no baseline edit could fix, since the baseline does declare the app.
#
# This throws rather than emitting a failing derivation: CI forces each check's
# drvPath with `nix eval` and never builds checks, so only an eval-time failure
# gates it (same rationale as modules/hosts/common/firewall-checks.nix).
{ config, lib, ... }:
let
  classify = config.flake.lib.nixos._hostAppsSubToggleClassify or null;

  # Shaped like the real snapshot: values are lib.mkOverride wrappers, which is
  # what the classifier has to unwrap before comparing.
  baseline = {
    programs = {
      "claude-code".extended.installMethods.bun.enable = lib.mkOverride 1100 false;
      firefoxpwa.dmail.enable = lib.mkOverride 1100 false;
      logseq.extended.disableGpuCompositing = lib.mkOverride 1100 false;
    };
    services = {
      espanso.extended.x11Override = lib.mkOverride 1100 false;
    };
  };

  toggle = path: value: { inherit path value; };

  cases = [
    {
      name = "programs path that diverges";
      toggles = [
        (toggle [ "logseq" "extended" "disableGpuCompositing" ] true)
      ];
      uncomparable = [ ];
      noOps = [ ];
    }
    {
      name = "programs path that duplicates the baseline";
      toggles = [
        (toggle [ "logseq" "extended" "disableGpuCompositing" ] false)
      ];
      uncomparable = [ ];
      noOps = [ "logseq.extended.disableGpuCompositing" ];
    }
    {
      # The branch that regressed: the app is a service, so a programs-only
      # lookup reports it as uncomparable even though the baseline declares it.
      name = "services path resolves in the services namespace";
      toggles = [
        (toggle [ "espanso" "extended" "x11Override" ] true)
      ];
      uncomparable = [ ];
      noOps = [ ];
    }
    {
      name = "services path that duplicates the baseline";
      toggles = [
        (toggle [ "espanso" "extended" "x11Override" ] false)
      ];
      uncomparable = [ ];
      noOps = [ "espanso.extended.x11Override" ];
    }
    {
      name = "path the baseline declares in neither namespace";
      toggles = [
        (toggle [ "logseq" "extended" "noSuchToggle" ] true)
      ];
      uncomparable = [ "logseq.extended.noSuchToggle" ];
      noOps = [ ];
    }
    {
      # A deeper path than the flat set's fixed extended.enable, which is the
      # whole reason this registry exists.
      name = "nested installMethods path";
      toggles = [
        (toggle [ "claude-code" "extended" "installMethods" "bun" "enable" ] false)
      ];
      uncomparable = [ ];
      noOps = [ "claude-code.extended.installMethods.bun.enable" ];
    }
    {
      name = "no toggles registered";
      toggles = [ ];
      uncomparable = [ ];
      noOps = [ ];
    }
  ];

  fmt = paths: "[ ${lib.concatStringsSep " " paths} ]";

  failures = lib.concatMap (
    case:
    let
      got = classify baseline case.toggles;
    in
    lib.optional (
      got.uncomparable != case.uncomparable
    ) "${case.name}: uncomparable ${fmt got.uncomparable}, expected ${fmt case.uncomparable}"
    ++ lib.optional (
      got.noOps != case.noOps
    ) "${case.name}: noOps ${fmt got.noOps}, expected ${fmt case.noOps}"
  ) cases;
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.host-apps-sub-toggle-classifier =
        if classify == null then
          throw (
            "host-apps-sub-toggle-classifier: modules/hosts/common/checks.nix no longer exports "
            + "flake.lib.nixos._hostAppsSubToggleClassify, so the sub-toggle comparison is unverified."
          )
        else if failures != [ ] then
          throw (
            "host-apps-sub-toggle-classifier: "
            + toString (lib.length failures)
            + " case(s) failed:\n  "
            + lib.concatStringsSep "\n  " failures
          )
        else
          pkgs.runCommandLocal "host-apps-sub-toggle-classifier-ok" { } ''
            echo "ok: ${toString (lib.length cases)} sub-toggle classifier cases" > $out
          '';
    };
}

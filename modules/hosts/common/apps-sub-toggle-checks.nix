# Coverage for the sub-toggle classifier and host-facing apply wrapper in
# modules/hosts/common/checks.nix.
#
# Host closures can reach both namespace lookups and the no-op branch through
# the registry. Full-path lookup checks programs first and falls back to
# services for services-only paths; a path absent from both namespaces fails
# either namespace pass.
#
# This throws rather than emitting a failing derivation: CI forces each check's
# drvPath with `nix eval` and never builds checks, so only an eval-time failure
# gates it (same rationale as modules/hosts/common/firewall-checks.nix).
{ config, lib, ... }:
let
  classify = config.flake.lib.nixos._hostAppsSubToggleClassify or null;
  mkApplySubToggles = config.flake.lib.nixos._mkHostAppsSubToggleApply or null;

  # Shaped like the real snapshot: values are lib.mkOverride wrappers, which is
  # what the classifier has to unwrap before comparing.
  baseline = {
    programs = {
      "claude-code".extended.installMethods.bun.enable = lib.mkOverride 1100 false;
      firefoxpwa.dmail.enable = lib.mkOverride 1100 false;
      logseq.extended.disableGpuCompositing = lib.mkOverride 1100 false;
      collision.extended.enable = lib.mkOverride 1100 false;
    };
    services = {
      espanso.extended.x11Override = lib.mkOverride 1100 false;
      collision.extended.x11Override = lib.mkOverride 1100 false;
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
      # A programs-only lookup would report this services app as uncomparable
      # even though the baseline declares it under services.
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

  # Write side. The classifier decides where a path is READ from; these decide
  # where it is WRITTEN. Full-path lookup gives programs precedence, uses
  # services only when the path is absent from programs, and throws on a path
  # absent from both namespaces.
  routingCases = [
    {
      name = "programs toggle lands under programs";
      namespace = "programs";
      toggles = [ (toggle [ "logseq" "extended" "disableGpuCompositing" ] true) ];
      present = true;
    }
    {
      name = "programs toggle does not land under services";
      namespace = "services";
      toggles = [ (toggle [ "logseq" "extended" "disableGpuCompositing" ] true) ];
      present = false;
    }
    {
      name = "services toggle lands under services";
      namespace = "services";
      toggles = [ (toggle [ "espanso" "extended" "x11Override" ] true) ];
      present = true;
    }
    {
      name = "services toggle does not land under programs";
      namespace = "programs";
      toggles = [ (toggle [ "espanso" "extended" "x11Override" ] true) ];
      present = false;
    }
    {
      name = "same-head programs path lands under programs";
      namespace = "programs";
      toggles = [ (toggle [ "collision" "extended" "enable" ] true) ];
      present = true;
    }
    {
      name = "same-head programs path does not land under services";
      namespace = "services";
      toggles = [ (toggle [ "collision" "extended" "enable" ] true) ];
      present = false;
    }
    {
      name = "same-head services-only path lands under services";
      namespace = "services";
      toggles = [ (toggle [ "collision" "extended" "x11Override" ] true) ];
      present = true;
    }
    {
      name = "same-head services-only path does not land under programs";
      namespace = "programs";
      toggles = [ (toggle [ "collision" "extended" "x11Override" ] true) ];
      present = false;
    }
    {
      # Every host evaluation runs this pass, so a registered path the baseline
      # stopped declaring fails the switch instead of vanishing from it.
      name = "unknown path fails the programs pass";
      namespace = "programs";
      toggles = [ (toggle [ "logseq" "extended" "noSuchToggle" ] true) ];
      throws = true;
    }
    {
      name = "unknown path fails the services pass";
      namespace = "services";
      toggles = [ (toggle [ "logseq" "extended" "noSuchToggle" ] true) ];
      throws = true;
    }
  ];

  routingFailures = lib.concatMap (
    case:
    let
      got = (mkApplySubToggles baseline case.toggles) case.namespace { };
      inherit ((lib.head case.toggles)) path;
      landed = lib.attrByPath path null got != null;
    in
    if case.throws or false then
      # The throw fires when the fold is forced, which the lookup above does;
      # an unexpected throw in the other cases propagates with its own message.
      lib.optional (builtins.tryEval landed).success "${case.name}: routed instead of throwing"
    else
      lib.optional (
        landed != case.present
      ) "${case.name}: landed=${lib.boolToString landed}, expected ${lib.boolToString case.present}"
  ) routingCases;

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

  allFailures = failures ++ routingFailures;
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.host-apps-sub-toggle-classifier =
        if classify == null || mkApplySubToggles == null then
          throw (
            "host-apps-sub-toggle-classifier: modules/hosts/common/checks.nix no longer exports "
            + "flake.lib.nixos._hostAppsSubToggleClassify and _mkHostAppsSubToggleApply, so the "
            + "sub-toggle comparison and routing are unverified."
          )
        else if allFailures != [ ] then
          throw (
            "host-apps-sub-toggle-classifier: "
            + toString (lib.length allFailures)
            + " case(s) failed:\n  "
            + lib.concatStringsSep "\n  " allFailures
          )
        else
          pkgs.runCommandLocal "host-apps-sub-toggle-classifier-ok" { } ''
            echo "ok: ${toString (lib.length cases + lib.length routingCases)} sub-toggle cases" > $out
          '';
    };
}

# Coverage for the override classifier and the host-facing builder in
# modules/hosts/common/checks.nix.
#
# Host closures can reach both namespace lookups and the no-op branch through
# the registries. Full-path lookup checks programs first and falls back to
# services for services-only paths; a path absent from both namespaces fails
# either namespace pass.
#
# This throws rather than emitting a failing derivation: CI forces each check's
# drvPath with `nix eval` and never builds checks, so only an eval-time failure
# gates it (same rationale as modules/hosts/common/firewall-checks.nix).
{ config, lib, ... }:
let
  classify = config.flake.lib.hostApps.classify or null;
  hostAppsFor = config.flake.lib.hostApps.forRegistry or null;
  formatCaseFailures = config.flake.lib.nixos._formatCheckFailures;

  # Shaped like the real snapshot: values are lib.mkOverride wrappers, which is
  # what the classifier has to unwrap before comparing.
  baseline = {
    programs = {
      "claude-code".extended.installMethods.bun.enable = lib.mkOverride 1100 false;
      firefoxpwa.dmail.enable = lib.mkOverride 1100 false;
      logseq.extended.disableGpuCompositing = lib.mkOverride 1100 false;
      inkscape.extended.enable = lib.mkOverride 1100 false;
      collision.extended.enable = lib.mkOverride 1100 false;
    };
    services = {
      espanso.extended.enable = lib.mkOverride 1100 false;
      espanso.extended.x11Override = lib.mkOverride 1100 false;
      collision.extended.x11Override = lib.mkOverride 1100 false;
    };
  };

  toggle = path: value: { inherit path value; };

  cases = [
    {
      name = "programs path that diverges";
      registry.subToggles = [
        (toggle [ "logseq" "extended" "disableGpuCompositing" ] true)
      ];
      uncomparable = [ ];
      noOps = [ ];
    }
    {
      name = "programs path that duplicates the baseline";
      registry.subToggles = [
        (toggle [ "logseq" "extended" "disableGpuCompositing" ] false)
      ];
      uncomparable = [ ];
      noOps = [ "logseq.extended.disableGpuCompositing" ];
    }
    {
      # A programs-only lookup would report this services app as uncomparable
      # even though the baseline declares it under services.
      name = "services path resolves in the services namespace";
      registry.subToggles = [
        (toggle [ "espanso" "extended" "x11Override" ] true)
      ];
      uncomparable = [ ];
      noOps = [ ];
    }
    {
      name = "services path that duplicates the baseline";
      registry.subToggles = [
        (toggle [ "espanso" "extended" "x11Override" ] false)
      ];
      uncomparable = [ ];
      noOps = [ "espanso.extended.x11Override" ];
    }
    {
      name = "path the baseline declares in neither namespace";
      registry.subToggles = [
        (toggle [ "logseq" "extended" "noSuchToggle" ] true)
      ];
      uncomparable = [ "logseq.extended.noSuchToggle" ];
      noOps = [ ];
    }
    {
      # A deeper path than the flat set's fixed extended.enable, which is the
      # whole reason this registry exists.
      name = "nested installMethods path";
      registry.subToggles = [
        (toggle [ "claude-code" "extended" "installMethods" "bun" "enable" ] false)
      ];
      uncomparable = [ ];
      noOps = [ "claude-code.extended.installMethods.bun.enable" ];
    }
    {
      # The flat set is the nested case with a fixed suffix, so it is reported
      # with that suffix.
      name = "flat entry that duplicates the baseline";
      registry.overrides.inkscape = false;
      uncomparable = [ ];
      noOps = [ "inkscape.extended.enable" ];
    }
    {
      name = "flat entry that diverges";
      registry.overrides.inkscape = true;
      uncomparable = [ ];
      noOps = [ ];
    }
    {
      name = "flat entry the baseline declares in neither namespace";
      registry.overrides.noSuchApp = true;
      uncomparable = [ "noSuchApp.extended.enable" ];
      noOps = [ ];
    }
    {
      name = "flat and nested entries classify together";
      registry = {
        overrides.inkscape = false;
        subToggles = [ (toggle [ "logseq" "extended" "noSuchToggle" ] true) ];
      };
      uncomparable = [ "logseq.extended.noSuchToggle" ];
      noOps = [ "inkscape.extended.enable" ];
    }
    {
      name = "nothing registered";
      registry = { };
      uncomparable = [ ];
      noOps = [ ];
    }
  ];

  # Write side. The classifier decides where a path is READ from; these decide
  # where it is WRITTEN. Full-path lookup gives programs precedence, uses
  # services only when the path is absent from programs, and throws on a path
  # absent from both namespaces. Each landed value must still be the
  # lib.mkOverride 1000 wrapper: the builder reaches host files through a
  # flake.lib option, and the anything type's merge would discharge the wrapper
  # into a priority-100 definition without any change in the switched value.
  routingCases = [
    {
      name = "programs toggle lands under programs";
      namespace = "programs";
      registry.subToggles = [ (toggle [ "logseq" "extended" "disableGpuCompositing" ] true) ];
      present = true;
    }
    {
      name = "programs toggle does not land under services";
      namespace = "services";
      registry.subToggles = [ (toggle [ "logseq" "extended" "disableGpuCompositing" ] true) ];
      present = false;
    }
    {
      name = "services toggle lands under services";
      namespace = "services";
      registry.subToggles = [ (toggle [ "espanso" "extended" "x11Override" ] true) ];
      present = true;
    }
    {
      name = "services toggle does not land under programs";
      namespace = "programs";
      registry.subToggles = [ (toggle [ "espanso" "extended" "x11Override" ] true) ];
      present = false;
    }
    {
      name = "same-head programs path lands under programs";
      namespace = "programs";
      registry.subToggles = [ (toggle [ "collision" "extended" "enable" ] true) ];
      present = true;
    }
    {
      name = "same-head programs path does not land under services";
      namespace = "services";
      registry.subToggles = [ (toggle [ "collision" "extended" "enable" ] true) ];
      present = false;
    }
    {
      name = "same-head services-only path lands under services";
      namespace = "services";
      registry.subToggles = [ (toggle [ "collision" "extended" "x11Override" ] true) ];
      present = true;
    }
    {
      name = "same-head services-only path does not land under programs";
      namespace = "programs";
      registry.subToggles = [ (toggle [ "collision" "extended" "x11Override" ] true) ];
      present = false;
    }
    {
      name = "flat programs entry lands under programs";
      namespace = "programs";
      registry.overrides.inkscape = true;
      present = true;
    }
    {
      name = "flat services entry lands under services";
      namespace = "services";
      registry.overrides.espanso = true;
      present = true;
    }
    {
      name = "flat services entry does not land under programs";
      namespace = "programs";
      registry.overrides.espanso = true;
      present = false;
    }
    {
      # Every host evaluation runs this pass, so a registered path the baseline
      # stopped declaring fails the switch instead of vanishing from it.
      name = "unknown path fails the programs pass";
      namespace = "programs";
      registry.subToggles = [ (toggle [ "logseq" "extended" "noSuchToggle" ] true) ];
      throws = true;
    }
    {
      name = "unknown path fails the services pass";
      namespace = "services";
      registry.subToggles = [ (toggle [ "logseq" "extended" "noSuchToggle" ] true) ];
      throws = true;
    }
    {
      name = "unknown flat entry fails the programs pass";
      namespace = "programs";
      registry.overrides.noSuchApp = true;
      throws = true;
    }
  ];

  # The single path each routing case registers, in the shape the registry
  # gives it.
  registeredPath =
    registry:
    if registry ? overrides then
      [
        (lib.head (lib.attrNames registry.overrides))
        "extended"
        "enable"
      ]
    else
      (lib.head registry.subToggles).path;
  registeredValue =
    registry:
    if registry ? overrides then
      lib.head (lib.attrValues registry.overrides)
    else
      (lib.head registry.subToggles).value;

  routingFailures = lib.concatMap (
    case:
    let
      got = (hostAppsFor "fixture" baseline case.registry).${case.namespace};
      landed = lib.attrByPath (registeredPath case.registry) null got;
      expectedLeaf = lib.mkOverride 1000 (registeredValue case.registry);
    in
    if case.throws or false then
      # The throw fires when the fold is forced, which the lookup above does;
      # an unexpected throw in the other cases propagates with its own message.
      lib.optional (builtins.tryEval (landed != null)).success "${case.name}: routed instead of throwing"
    else if case.present then
      lib.optional (landed != expectedLeaf)
        "${case.name}: landed as ${
          lib.generators.toPretty { } landed
        }, expected the lib.mkOverride 1000 wrapper"
    else
      lib.optional (landed != null) "${case.name}: landed under ${case.namespace}"
  ) routingCases;

  fmt = paths: "[ ${lib.concatStringsSep " " paths} ]";

  failures = lib.concatMap (
    case:
    let
      got = classify baseline case.registry;
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
        if classify == null || hostAppsFor == null then
          throw (
            "host-apps-sub-toggle-classifier: modules/hosts/common/checks.nix no longer exports "
            + "flake.lib.hostApps.classify and flake.lib.hostApps.forRegistry, so the "
            + "override comparison and routing are unverified."
          )
        else if allFailures != [ ] then
          throw (formatCaseFailures "host-apps-sub-toggle-classifier" allFailures)
        else
          pkgs.runCommandLocal "host-apps-sub-toggle-classifier-ok" { } ''
            echo "ok: ${toString (lib.length cases + lib.length routingCases)} sub-toggle cases" > $out
          '';
    };
}

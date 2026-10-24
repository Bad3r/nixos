# Per host, the app registry decides what runs and what is installed: only the
# baseline (1100), a host row (1000), or a prerequisite turning a row on (1050)
# sets a toggle the baseline declares, and no module installs the package of an
# app whose row is off unless the NixOS base installs it too.
{ config, lib, ... }:
let
  prerequisitePriority = 1050;
  baseline = config.flake.lib.nixos._commonAppsBaseline;
  formatCheckFailures = config.flake.lib.nixos._formatCheckFailures;

  isOverride = value: lib.isAttrs value && (value._type or "") == "override";
  togglesOf =
    prefix: set:
    lib.concatLists (
      lib.mapAttrsToList (
        name: value:
        if builtins.isBool value then
          [
            {
              path = prefix ++ [ name ];
              inherit value;
            }
          ]
        else if isOverride value then
          lib.optional (builtins.isBool value.content) {
            path = prefix ++ [ name ];
            value = value.content;
          }
        else if lib.isAttrs value then
          togglesOf (prefix ++ [ name ]) value
        else
          [ ]
      ) set
    );
  baselineToggles =
    togglesOf [ "programs" ] baseline.programs ++ togglesOf [ "services" ] baseline.services;

  registeredHosts =
    config.flake.lib.nixos._hostAppsOverrides // config.flake.lib.nixos._hostAppsSubToggleOverrides;
  sharedHosts = lib.filterAttrs (
    name: _: config.flake.lib.nixos._isShareCommonHost name
  ) config.flake.nixosConfigurations;

  failuresOf =
    host: nixos:
    let
      hostApps =
        if registeredHosts ? ${host} then
          config.flake.lib.hostApps.mk host
        else
          {
            programs = { };
            services = { };
          };
      outPathSet =
        packages:
        lib.genAttrs (map (package: builtins.unsafeDiscardStringContext package.outPath) packages) (
          _: true
        );
      installed = outPathSet (
        nixos.config.environment.systemPackages
        ++ lib.concatMap (user: user.home.packages) (lib.attrValues nixos.config.home-manager.users)
      );
      # NixOS installs its core and default packages whatever the rows say.
      installedByBase = outPathSet (
        nixos.config.environment.corePackages ++ nixos.config.environment.defaultPackages
      );

      checkToggle =
        toggle:
        let
          name = lib.concatStringsSep "." toggle.path;
          hostOverride = lib.attrByPath toggle.path null hostApps;
          expected = if hostOverride == null then toggle.value else hostOverride.content;
          actual = lib.getAttrFromPath toggle.path nixos.config;
          priority = (lib.getAttrFromPath toggle.path nixos.options).highestPrio;
          setByRegistry = priority == (if hostOverride == null then 1100 else 1000) && actual == expected;
          prerequisite = actual && priority == prerequisitePriority;

          isEnableRow =
            lib.drop 2 toggle.path == [
              "extended"
              "enable"
            ];
          packageOption = lib.attrByPath (
            lib.take 2 toggle.path
            ++ [
              "extended"
              "package"
            ]
          ) null nixos.options;
          defaultText = packageOption.defaultText or null;
          defaultSource =
            if builtins.isAttrs defaultText then
              defaultText.text or ""
            else if builtins.isString defaultText then
              defaultText
            else
              "";
          # A gated overlay drops its attribute while the row is off, which
          # tryEval cannot catch, so such a default is skipped.
          pkgsAttr = builtins.match ''pkgs\."?([^".]+).*'' defaultSource;
          packageReachable =
            packageOption.highestPrio < 1500 || pkgsAttr == null || nixos.pkgs ? ${builtins.head pkgsAttr};
          packageOutPath = builtins.tryEval (builtins.unsafeDiscardStringContext packageOption.value.outPath);
          installedWhileOff =
            isEnableRow
            && !actual
            && packageOption != null
            && packageReachable
            && packageOutPath.success
            && installed ? ${packageOutPath.value}
            && !(installedByBase ? ${packageOutPath.value});
        in
        lib.optional (!setByRegistry && !prerequisite) (
          "${host}: ${name} is ${lib.boolToString actual} at priority ${toString priority}; only "
          + "modules/hosts/common/apps-enable.nix (1100), modules/hosts/${host}/apps-enable.nix (1000), or a "
          + "prerequisite turning it on (lib.mkOverride ${toString prerequisitePriority} true) may set it, "
          + "and the registry sets ${lib.boolToString expected}"
        )
        ++ lib.optional installedWhileOff (
          "${host}: ${name} is off, yet ${packageOption.value.name} is installed; "
          + "remove the install that bypasses the row, or turn the row on"
        );
    in
    lib.concatMap checkToggle baselineToggles;
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks = lib.mapAttrs' (
        host: nixos:
        let
          failures = failuresOf host nixos;
        in
        lib.nameValuePair "host-${host}-apps-match-registry" (
          if failures != [ ] then
            throw (formatCheckFailures "host-${host}-apps-match-registry" failures)
          else
            pkgs.runCommandLocal "host-${host}-apps-match-registry-ok" { } ''
              echo "ok: ${host} runs and installs exactly what its app registry rows say" > $out
            ''
        )
      ) sharedHosts;
    };
}

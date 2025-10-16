{
  config,
  ...
}:
let
  helpers = config.flake.lib.nixos or { };
  assertList = v: if builtins.isList v then true else throw "role module imports not a list";
in
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (pkgs) lib;
      mkEvalCheck = name: expr: builtins.seq expr (pkgs.runCommand name { } "touch $out");
      taxonomyForSystem = import ../../lib/taxonomy { inherit lib; };
      modules = config.flake.nixosModules or { };
      flakeConfigs = config.flake.nixosConfigurations or { };
      inputsAttr = config._module.args.inputs or { };
      registryEntries = builtins.fromJSON (builtins.readFile ../../docs/RFC-0001/manifest-registry.json);
      manifestHosts = lib.filter (
        entry: (entry ? host) && entry.host != null && entry.host != ""
      ) registryEntries;
      roleHelpers = (config._module.args.nixosRoleHelpers or { }) // (helpers.roles or { });
      resolveRole = roleHelpers.getRole or (_: null);
      roleModuleExists =
        name:
        let
          attempt = builtins.tryEval (resolveRole name);
        in
        attempt.success && attempt.value != null;

      normalizePkgName =
        pkg:
        let
          rawName =
            pkg.pname or (
              if pkg ? name then
                (builtins.parseDrvName pkg.name).name
              else
                let
                  drvName = builtins.parseDrvName (
                    builtins.baseNameOf (builtins.unsafeDiscardStringContext (toString pkg))
                  );
                in
                drvName.name
            );
          withoutHash =
            let
              m = builtins.match "^[0-9a-z]{32}-(.*)$" rawName;
            in
            if m == null then rawName else builtins.head m;
          withoutVersion =
            let
              m = builtins.match "^(.*?)-[0-9].*$" withoutHash;
            in
            if m == null then withoutHash else builtins.head m;
        in
        withoutVersion;

      packagesForHost =
        host:
        let
          cfg = if lib.hasAttr host flakeConfigs then lib.getAttr host flakeConfigs else null;
        in
        if cfg == null then
          throw "phase0-host-package-guard: host '${host}' missing from flake.nixosConfigurations"
        else
          let
            pkgsList = cfg.config.environment.systemPackages or [ ];
            normalized = builtins.map normalizePkgName pkgsList;
            sorted = builtins.sort (a: b: a < b) normalized;
          in
          lib.unique sorted;

      actualPackageMap = builtins.listToAttrs (
        map (entry: {
          name = entry.host;
          value = packagesForHost entry.host;
        }) manifestHosts
      );

      actualPackagesJson = pkgs.writeText "phase0-host-package-guard-actual.json" (
        builtins.toJSON actualPackageMap
      );

      inputStorePaths =
        let
          toPathString =
            _name: value:
            if value ? outPath then
              toString value.outPath
            else if value ? packages && value.packages ? "x86_64-linux" then
              toString value.packages."x86_64-linux"
            else
              "";
        in
        lib.concatStringsSep " " (
          lib.filter (path: path != "") (lib.mapAttrsToList toPathString inputsAttr)
        );
    in
    {
      checks = {
        role-modules-exist = mkEvalCheck "role-modules-exist-ok" (
          if
            roleModuleExists "development.core"
            && roleModuleExists "audio-video.media"
            && roleModuleExists "network.tools"
          then
            "ok"
          else
            throw "role module missing"
        );

        role-modules-structure = mkEvalCheck "role-modules-structure-ok" (
          builtins.seq (assertList (resolveRole "development.core").imports) (
            builtins.seq (assertList (resolveRole "audio-video.media").imports) (
              builtins.seq (assertList (resolveRole "network.tools").imports) "ok"
            )
          )
        );

        helpers-exist = mkEvalCheck "helpers-exist-ok" (
          if (helpers ? getApp) && (helpers ? getApps) && (helpers ? getAppOr) && (helpers ? hasApp) then
            "ok"
          else
            throw "missing helper(s) under config.flake.lib.nixos"
        );

        taxonomy-overrides = mkEvalCheck "taxonomy-overrides-ok" (
          let
            overrideNames = builtins.attrNames taxonomyForSystem.overrides;
            problems = builtins.concatMap (
              pkg:
              let
                result = taxonomyForSystem.validateMetadata (taxonomyForSystem.resolveOverride pkg);
              in
              if result.valid then
                [ ]
              else
                [
                  "${pkg}: ${lib.concatStringsSep "; " result.errors}"
                ]
            ) overrideNames;
          in
          if problems == [ ] then
            "ok"
          else
            throw ("taxonomy metadata override issues:\n" + lib.concatStringsSep "\n" problems)
        );

        phase0-taxonomy-version = mkEvalCheck "phase0-taxonomy-version-ok" (
          let
            result = import ../../checks/phase0/taxonomy-version.nix { inherit lib; };
          in
          if result.valid then
            "ok"
          else
            throw ("taxonomy version mismatch:\n" + lib.concatStringsSep "\n" result.errors)
        );

        phase0-host-package-guard =
          pkgs.runCommand "phase0-host-package-guard"
            {
              nativeBuildInputs = [
                pkgs.coreutils
                pkgs.findutils
                pkgs.jq
                pkgs.nix
                pkgs.python3
                pkgs.bash
              ];
              ROOT_PATH = config._module.args.rootPath;
              HOST_PACKAGE_GUARD_REGISTRY = ../../docs/RFC-0001/manifest-registry.json;
              HOST_PACKAGE_GUARD_ACTUAL_JSON = actualPackagesJson;
            }
            ''
              set -euo pipefail
              export HOME="$TMPDIR"
              export NIX_CONFIG=$'experimental-features = nix-command flakes\nsandbox = false'
              ${pkgs.bash}/bin/bash ${../../checks/phase0/host-package-guard.sh} "$ROOT_PATH"
              touch "$out"
            '';

        phase0-role-imports =
          pkgs.runCommand "phase0-role-imports"
            {
              nativeBuildInputs = [
                pkgs.coreutils
                pkgs.nix
                pkgs.python3
              ];
              ROOT_PATH = config._module.args.rootPath;
              INPUT_STORE_PATHS = inputStorePaths;
            }
            ''
                            set -euo pipefail
                            export HOME="$TMPDIR"
                            export NIX_CONFIG=$'experimental-features = nix-command flakes\nsandbox = false'
                            for store_path in $INPUT_STORE_PATHS; do
                              if [ -n "$store_path" ]; then
                                ls "$store_path" >/dev/null 2>&1 || true
                              fi
                            done
                            report="$TMPDIR/role-imports.json"
                            python3 ${../../scripts/list-role-imports.py} --offline --repo "$ROOT_PATH" --format json > "$report"
                            python3 - "$report" <<'PY'
              import json
              import sys
              from pathlib import Path

              report_path = Path(sys.argv[1])
              data = json.loads(report_path.read_text())

              app_roles = {}
              for role, info in data.items():
                  for app in info.get("apps", []):
                      app_roles.setdefault(app, set()).add(role)

              duplicates = {app: sorted(list(roles)) for app, roles in app_roles.items() if len(roles) > 1}

              if duplicates:
                  sys.stderr.write("role-imports: duplicate app payloads detected across roles:\\n")
                  for app, roles in sorted(duplicates.items()):
                      sys.stderr.write(f"  {app}: {', '.join(roles)}\\n")
                  sys.exit(1)

              if not data:
                  sys.stderr.write("role-imports: reporter returned no roles; cannot audit imports\\n")
                  sys.exit(1)
              PY
                            cp "$report" "$out"
            '';

        phase0-profile-purity = mkEvalCheck "phase0-profile-purity-ok" (
          let
            result = import ../../checks/phase0/profile-purity.nix {
              inherit lib;
              flakeModules = modules;
              profileName = "workstation";
            };
          in
          if result.valid then
            "ok"
          else
            throw (
              "profiles.workstation imports violate role purity:\n" + lib.concatStringsSep "\n" result.errors
            )
        );

        phase0-alias-registry = mkEvalCheck "phase0-alias-registry-ok" (
          let
            result = import ../../checks/phase0/alias-resolver.nix { inherit lib; };
          in
          if result.valid then
            "ok"
          else
            throw ("role alias registry issues:\n" + lib.concatStringsSep "\n" result.errors)
        );

        phase0-metadata = mkEvalCheck "phase0-metadata-ok" (
          let
            result = import ../../checks/phase0/metadata-lint.nix {
              inherit lib;
              flakeModules = modules;
            };
          in
          if result.valid then
            "ok"
          else
            throw ("role metadata issues:\n" + lib.concatStringsSep "\n" result.errors)
        );

        role-extras-present = mkEvalCheck "role-extras-present-ok" (
          let
            role = resolveRole "development.core";
            hasNixLd = builtins.any (
              module:
              let
                applied = module {
                  inherit pkgs lib;
                  config = { };
                };
                enableFlag =
                  (applied ? programs && applied.programs ? nix-ld && applied.programs.nix-ld.enable or false)
                  || (
                    applied ? _module
                    && applied._module ? config
                    && applied._module.config ? programs
                    && applied._module.config.programs ? nix-ld
                    && applied._module.config.programs.nix-ld.enable or false
                  );
              in
              enableFlag
            ) role.imports;
          in
          if hasNixLd then
            "ok"
          else
            throw "role extras missing: development.core no longer enables programs.nix-ld"
        );

        phase4-workstation-parity =
          pkgs.runCommand "phase4-workstation-parity"
            {
              nativeBuildInputs = [
                pkgs.coreutils
                pkgs.python3
              ];
              WORKSTATION_PARITY_MANIFEST = ../../docs/RFC-0001/workstation-packages.json;
              WORKSTATION_PARITY_ACTUAL = actualPackagesJson;
              WORKSTATION_PARITY_HOST = "system76";
              PACKAGE_UTILS_DIR = ../../scripts;
            }
            ''
              set -euo pipefail
              export HOME="$TMPDIR"
              if [[ -n "${"PYTHONPATH:-"}" ]]; then
                export PYTHONPATH="$PACKAGE_UTILS_DIR:$PYTHONPATH"
              else
                export PYTHONPATH="$PACKAGE_UTILS_DIR"
              fi
              python3 ${../../checks/phase4/workstation-parity.py} \
                --manifest "$WORKSTATION_PARITY_MANIFEST" \
                --actual "$WORKSTATION_PARITY_ACTUAL" \
                --host "$WORKSTATION_PARITY_HOST"
              touch "$out"
            '';
      };
    };
}

{
  config,
  withSystem,
  ...
}:
let
  helpers = config.flake.lib.nixos or { };
  assertList = v: if builtins.isList v then true else throw "role module imports not a list";
  hasRoles = builtins.hasAttr "roles" config.flake.nixosModules;
  roleModuleExists =
    name: if hasRoles then builtins.hasAttr name config.flake.nixosModules.roles else false;
  defaultSystem = builtins.head config.systems;
  defaultLib = withSystem defaultSystem (psArgs: psArgs.pkgs.lib);
  mkEvalCheck =
    name: expr:
    withSystem defaultSystem (psArgs: builtins.seq expr (psArgs.pkgs.runCommand name { } "touch $out"));
in
{
  flake.checks = {
    role-modules-exist = mkEvalCheck "role-modules-exist-ok" (
      if roleModuleExists "dev" && roleModuleExists "media" && roleModuleExists "net" then
        "ok"
      else
        throw "role module missing"
    );

    role-modules-structure = mkEvalCheck "role-modules-structure-ok" (
      builtins.seq (assertList config.flake.nixosModules.roles.dev.imports) (
        builtins.seq (assertList config.flake.nixosModules.roles.media.imports) (
          builtins.seq (assertList config.flake.nixosModules.roles.net.imports) "ok"
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
        lib = defaultLib;
        taxonomy = import ../../lib/taxonomy { inherit lib; };
        overrideNames = builtins.attrNames taxonomy.overrides;
        problems = builtins.concatMap (
          pkg:
          let
            result = taxonomy.validateMetadata (taxonomy.resolveOverride pkg);
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
        lib = defaultLib;
        result = import ../../checks/phase0/taxonomy-version.nix { inherit lib; };
      in
      if result.valid then
        "ok"
      else
        throw (
          "taxonomy version mismatch:\n"
          + lib.concatStringsSep "\n" result.errors
        )
    );

    phase0-host-package-guard = withSystem defaultSystem (
      psArgs:
      let
        pkgs = psArgs.pkgs;
      in
      pkgs.runCommand "phase0-host-package-guard"
        {
          nativeBuildInputs = [
            pkgs.coreutils
            pkgs.findutils
            pkgs.jq
            pkgs.nix
          ];
          ROOT_PATH = builtins.toString config._module.args.rootPath;
        }
        ''
          set -euo pipefail
          export HOME="$TMPDIR"
          export NIX_CONFIG="experimental-features = nix-command flakes"
          ${../../checks/phase0/host-package-guard.sh} "$ROOT_PATH"
          touch "$out"
        ''
    );

    phase0-profile-purity = mkEvalCheck "phase0-profile-purity-ok" (
      let
        lib = defaultLib;
        modules = config.flake.nixosModules or { };
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
        lib = defaultLib;
        result = import ../../checks/phase0/alias-resolver.nix { inherit lib; };
      in
      if result.valid then
        "ok"
      else
        throw ("role alias registry issues:\n" + lib.concatStringsSep "\n" result.errors)
    );

    phase0-metadata = mkEvalCheck "phase0-metadata-ok" (
      let
        lib = defaultLib;
        modules = config.flake.nixosModules or { };
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
  };

  perSystem = _: { };
}

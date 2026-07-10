# RFC #282: hosts take Lix from the nixpkgs pin (lixPackageSets.latest.lix,
# modules/base/nix-package.nix) while CI installs a pinned install.lix.systems
# release (.github/actions/install-lix/action.yml). Nothing else couples the
# two version sources, so either bump alone would silently desync what CI
# validates from what hosts run. This check compares every pinned installer
# version (the action's LIX_VERSION plus any inline install.lix.systems URL
# in a workflow) against the host package version, and fails when the action
# pin cannot be found at all so a rename cannot make the comparison vacuous.
# throw, not a failing derivation: CI runs `nix flake check --no-build`,
# which evaluates check attrs but never builds them, so only an eval-time
# failure gates CI.
{ lib, ... }:
let
  actionFile = ../../.github/actions/install-lix/action.yml;
  workflowsDir = ../../.github/workflows;

  linesOf = file: lib.splitString "\n" (builtins.readFile file);

  lixVersionOf =
    line: builtins.match ''[[:space:]]*LIX_VERSION:[[:space:]]*"?([0-9][0-9.]*)"?[[:space:]]*'' line;
  urlVersionOf = line: builtins.match ''.*install\.lix\.systems/lix/([0-9][0-9.]*)/.*'' line;

  pinsIn =
    matcher: file:
    lib.concatMap (
      line:
      let
        m = matcher line;
      in
      if m == null then [ ] else m
    ) (linesOf file);

  workflowFiles = lib.mapAttrsToList (name: _: workflowsDir + "/${name}") (
    lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".yml" name) (
      builtins.readDir workflowsDir
    )
  );

  actionPins = pinsIn lixVersionOf actionFile ++ pinsIn urlVersionOf actionFile;
  workflowPins = lib.concatMap (pinsIn urlVersionOf) workflowFiles;
  pins = lib.unique (actionPins ++ workflowPins);
in
{
  perSystem =
    { pkgs, ... }:
    let
      hostVersion = pkgs.lixPackageSets.latest.lix.version;
      stale = builtins.filter (v: v != hostVersion) pins;
    in
    {
      checks.ci-lix-installer-parity =
        if actionPins == [ ] then
          throw "ci-lix-installer-parity: no LIX_VERSION pin found in .github/actions/install-lix/action.yml"
        else if stale != [ ] then
          throw (
            "ci-lix-installer-parity: CI pins Lix ${lib.concatStringsSep ", " stale} "
            + "but lixPackageSets.latest.lix is ${hostVersion}; bump LIX_VERSION and "
            + "INSTALLER_SHA256 in .github/actions/install-lix/action.yml together "
            + "with the nixpkgs pin"
          )
        else
          pkgs.runCommandLocal "ci-lix-installer-parity-ok" { } ''
            echo "ok: CI installer pin ${hostVersion} matches lixPackageSets.latest.lix" > $out
          '';
    };
}

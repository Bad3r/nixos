/*
  CI substituter parity (issue #382)

  The Lix installer writes no substituters, so a runner reads cache.nixos.org
  alone unless .github/actions/install-lix appends the generated
  substituters.conf to NIX_INSTALLER_EXTRA_CONF. Without it cache-push
  rebuilds every cache root on each push, including the closure it pushed an
  hour earlier. This module generates that file from the host cache list that
  modules/hosts/common/nix-substituters.nix exports, and fails evaluation when
  the action stops appending it or drops the step that verifies the installed
  result. throw, not a failing derivation, for the reason ci-lix-parity gives:
  CI runs `nix flake check --no-build`.
*/
{ config, lib, ... }:
let
  substituterConfPath = ".github/actions/install-lix/substituters.conf";
  actionFile = ../../.github/actions/install-lix/action.yml;

  caches =
    config.flake.lib.nixos.substituterCaches
      or (throw "modules/hosts/common/nix-substituters.nix no longer exports flake.lib.nixos.substituterCaches");

  # Uncommented lines only: commenting the append out is how it gets disabled,
  # and every infix below survives inside a comment. Same hazard
  # bootstrap-substituter-parity guards against in build.sh.
  codeLines = lib.filter (line: builtins.match "[[:space:]]*#.*" line == null) (
    lib.splitString "\n" (builtins.readFile actionFile)
  );
  hasLine = pred: lib.any pred codeLines;

  appendsConf =
    hasLine (lib.hasInfix ''conf="$GITHUB_ACTION_PATH/${baseNameOf substituterConfPath}"'')
    && hasLine (
      line: lib.hasInfix "NIX_INSTALLER_EXTRA_CONF=" line && lib.hasInfix ''$(cat "$conf")'' line
    )
    # The installer re-emits the payload from a parsed key map and can drop a
    # line, which no eval-time match can observe. The runtime step is the only
    # guard for that, so its survival is asserted too.
    && hasLine (lib.hasInfix ''nix config show "$setting"'');
in
{
  perSystem =
    { pkgs, ... }:
    {
      files.file.${substituterConfPath}.text = ''
        extra-substituters = ${lib.concatMapStringsSep " " (cache: cache.url) caches}
        extra-trusted-public-keys = ${lib.concatMapStringsSep " " (cache: cache.key) caches}
      '';

      checks.ci-substituter-parity =
        if appendsConf then
          pkgs.runCommandLocal "ci-substituter-parity" { } "touch $out"
        else
          throw "ci-substituter-parity: .github/actions/install-lix/action.yml no longer appends ${substituterConfPath} to NIX_INSTALLER_EXTRA_CONF on an uncommented line, or dropped the step that verifies the installed substituters; CI would rebuild every cache root on each push";
    };
}

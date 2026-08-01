/*
  Bootstrap substituter parity (issue #382)

  `configure_nix_config` in build.sh writes `substituters = ...`, replacing the
  daemon's list rather than extending it, so a cache hosts trust through
  modules/hosts/common/nix-substituters.nix but that BOOTSTRAP_SUBSTITUTERS
  omits is unreachable for the one build that runs before that module is
  active: a fresh machine with nothing in its store. The drift is silent,
  because the build still succeeds. It just rebuilds locally everything the
  missing cache would have served.

  The comparison is directional and covers every registered host. build.sh
  bootstraps whichever host it runs on (`TARGET_HOST="$(hostname)"`, with a
  `--host` override), so a cache that reaches only one host's nix.settings,
  through a host-specific module or an app that per-host apps-enable.nix turns
  on for one host and not the other, still has to be in the arrays. Every
  substituter and key any host trusts must appear there; the reverse is not
  required, since build.sh also carries region mirrors for other networks.

  extra-substituters counts the same as substituters. configure_nix_config
  replaces the whole list, so a cache that reaches the daemon through
  `nix.settings.extra-substituters` (how modules/apps/doom-emacs.nix and
  modules/apps/logseq.nix wire theirs) is exactly as unreachable during
  bootstrap as one reaching it through `substituters`.
*/
{ config, lib, ... }:
let
  # Only decides which perSystem instance carries the check. The comparison
  # below reads every registered host.
  checkHost = "system76";

  buildScriptLines = lib.splitString "\n" (builtins.readFile ../../build.sh);

  # Quoted entries between `<name>=(` and its closing `)`. A commented-out
  # entry starts with `#`, so the quote match fails and a disabled mirror does
  # not count as configured.
  #
  # An array that is never opened or never closed throws. Without that, a
  # closing paren gaining a comment would leave the fold collecting quoted
  # lines to EOF, yielding a strict superset of the real array: every
  # comparison below would then find nothing missing and pass forever. The
  # emptiness guard cannot catch that, because the over-wide list is large.
  arrayEntries =
    name:
    let
      step =
        state: line:
        if state.done then
          state
        else if !state.inside then
          state // { inside = line == "${name}=("; }
        else if lib.hasPrefix ")" line then
          state
          // {
            inside = false;
            done = true;
          }
        else
          let
            m = builtins.match "[[:space:]]*\"([^\"]+)\".*" line;
          in
          if m == null then state else state // { entries = state.entries ++ [ (lib.head m) ]; };
      parsed = lib.foldl' step {
        inside = false;
        done = false;
        entries = [ ];
      } buildScriptLines;
    in
    if parsed.done then
      parsed.entries
    else
      throw "bootstrap-substituter-parity: build.sh has no closed ${name}=( ... ) array; the comparison would otherwise run against an over-wide list";

  # The NixOS module default contributes cache.nixos.org with a trailing slash
  # and build.sh spells it without one; they address the same store.
  normalize = lib.removeSuffix "/";

  bootstrapSubstituters = map normalize (arrayEntries "BOOTSTRAP_SUBSTITUTERS");
  bootstrapKeys = arrayEntries "BOOTSTRAP_TRUSTED_KEYS";
in
{
  perSystem =
    { pkgs, system, ... }:
    let
      checkSystem = config.flake.nixosConfigurations.${checkHost}.pkgs.stdenv.hostPlatform.system;

      missing = lib.concatLists (
        lib.mapAttrsToList (
          host: node:
          let
            settings = node.config.nix.settings;
            substituters = map normalize (settings.substituters ++ (settings.extra-substituters or [ ]));
            keys = settings.trusted-public-keys ++ (settings.extra-trusted-public-keys or [ ]);
          in
          map (entry: "${host} trusts ${entry}") (
            lib.subtractLists bootstrapSubstituters substituters ++ lib.subtractLists bootstrapKeys keys
          )
        ) config.flake.nixosConfigurations
      );
    in
    {
      checks = lib.mkIf (checkSystem == system) {
        bootstrap-substituter-parity =
          # An empty parse means the arrays were renamed or reshaped. That must
          # fail rather than compare nothing and pass.
          if bootstrapSubstituters == [ ] || bootstrapKeys == [ ] then
            throw "bootstrap-substituter-parity: parsed no BOOTSTRAP_SUBSTITUTERS or BOOTSTRAP_TRUSTED_KEYS entries out of build.sh; a rename would make this comparison vacuous"
          else if missing != [ ] then
            throw (
              "bootstrap-substituter-parity: "
              + lib.concatStringsSep "; " missing
              + " but build.sh omits it. configure_nix_config replaces the substituter list rather than "
              + "extending it, so build.sh --bootstrap cannot substitute from that cache. Add it to "
              + "BOOTSTRAP_SUBSTITUTERS and BOOTSTRAP_TRUSTED_KEYS."
            )
          else
            pkgs.runCommand "bootstrap-substituter-parity" { } "touch $out";
      };
    };
}

/*
  Bootstrap substituter parity (issue #382)

  `configure_nix_config` in build.sh writes `substituters = ...`, replacing the
  daemon's list rather than extending it, so a cache hosts trust through
  modules/hosts/common/nix-substituters.nix but that BOOTSTRAP_SUBSTITUTERS
  omits is unreachable for the one build that runs before that module is
  active: a fresh machine with nothing in its store. The drift is silent,
  because the build still succeeds. It just rebuilds locally everything the
  missing cache would have served.

  The comparison is directional. Every substituter and key the primary host
  trusts must appear in the bootstrap arrays; the reverse is not required,
  since build.sh also carries region mirrors for other networks.

  extra-substituters counts the same as substituters. configure_nix_config
  replaces the whole list, so a cache that reaches the daemon through
  `nix.settings.extra-substituters` (how modules/apps/doom-emacs.nix and
  modules/apps/logseq.nix wire theirs) is exactly as unreachable during
  bootstrap as one reaching it through `substituters`.
*/
{ config, lib, ... }:
let
  primaryHost = "system76";

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
      hostConfig = config.flake.nixosConfigurations.${primaryHost}.config;
      hostSystem = config.flake.nixosConfigurations.${primaryHost}.pkgs.stdenv.hostPlatform.system;

      missingSubstituters = lib.subtractLists bootstrapSubstituters (
        map normalize (
          hostConfig.nix.settings.substituters ++ (hostConfig.nix.settings.extra-substituters or [ ])
        )
      );
      missingKeys = lib.subtractLists bootstrapKeys (
        hostConfig.nix.settings.trusted-public-keys
        ++ (hostConfig.nix.settings.extra-trusted-public-keys or [ ])
      );
    in
    {
      checks = lib.mkIf (hostSystem == system) {
        bootstrap-substituter-parity =
          # An empty parse means the arrays were renamed or reshaped. That must
          # fail rather than compare nothing and pass.
          if bootstrapSubstituters == [ ] || bootstrapKeys == [ ] then
            throw "bootstrap-substituter-parity: parsed no BOOTSTRAP_SUBSTITUTERS or BOOTSTRAP_TRUSTED_KEYS entries out of build.sh; a rename would make this comparison vacuous"
          else if missingSubstituters != [ ] || missingKeys != [ ] then
            throw (
              "bootstrap-substituter-parity: ${primaryHost} trusts "
              + lib.concatStringsSep ", " (missingSubstituters ++ missingKeys)
              + " but build.sh omits it. configure_nix_config replaces the substituter list rather than "
              + "extending it, so build.sh --bootstrap cannot substitute from that cache. Add it to "
              + "BOOTSTRAP_SUBSTITUTERS and BOOTSTRAP_TRUSTED_KEYS."
            )
          else
            pkgs.runCommand "bootstrap-substituter-parity" { } "touch $out";
      };
    };
}

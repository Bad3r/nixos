# A gitleaks allowlist entry under `paths` skips the whole file before its
# contents are scanned, so path-scoping a tree hides every real credential in
# it, not just the false positive the entry was added for. Measured with
# gitleaks 8.30.1: allowlisting secrets/private-ops/.* dropped the scan of that
# file to 0 bytes and a planted Stripe live key and Slack bot token in it both
# went undetected. Path matching is unanchored, so a pattern need not spell
# "secrets" to reach the same file ("private-ops/.*" skips it too). The guard is
# therefore an inverted allowlist: only the reviewed nixos-manual paths may
# path-scope at all, and every other false positive must be scoped by content.
# throw, not a failing derivation: CI runs `nix flake check --no-build`,
# which evaluates check attrs but never builds them, so only an eval-time
# failure gates CI.
{ lib, ... }:
{
  perSystem =
    { config, pkgs, ... }:
    let
      # The Nix definition, not the regenerated .gitleaks.toml: a source edit
      # that never went through write-files would otherwise pass this check and
      # leave only the local managed-files-drift hook between it and main.
      cfg = builtins.fromTOML config.files.file.".gitleaks.toml".text;

      # Structural parse rather than string splitting, because `paths=[` without
      # spaces, a reordered key, or an inline table all defeat an infix search,
      # and a guard that a whitespace change disarms is not a guard. gitleaks
      # still accepts the singular [allowlist] table, so fold that in too.
      allowlists = (cfg.allowlists or [ ]) ++ lib.optional (cfg ? allowlist) cfg.allowlist;

      unreviewedPathScope = lib.filter (
        a: lib.any (p: !lib.hasInfix "nixos-manual" p) (a.paths or [ ])
      ) allowlists;

      # The Cloudflare KV allowlist is a no-op unless it is line-scoped: against
      # the default target the regex is matched on the bare hex secret and never
      # sees the surrounding "keys KV:" text.
      kvBlocks = lib.filter (a: lib.any (lib.hasInfix "keys KV") (a.regexes or [ ])) allowlists;
      kvUnscoped = lib.filter (a: (a.regexTarget or "secret") != "line") kvBlocks;

      describe = entries: lib.concatMapStringsSep ", " (a: a.description or "<undescribed>") entries;
    in
    {
      checks.gitleaks-allowlist-scope =
        if unreviewedPathScope != [ ] then
          throw (
            "gitleaks-allowlist-scope: allowlist ${describe unreviewedPathScope} path-scopes a tree "
            + "outside the reviewed nixos-manual set. A paths entry makes gitleaks skip those files "
            + "entirely, hiding real leaks in them, and matching is unanchored so the pattern need not "
            + "name the tree it reaches. Scope by content with regexTarget = \"line\" instead, or "
            + "extend this check deliberately (modules/development/gitleaks.nix)"
          )
        else if kvBlocks == [ ] then
          throw (
            "gitleaks-allowlist-scope: the Cloudflare KV namespace allowlist is gone from "
            + "modules/development/gitleaks.nix; drop this check along with it"
          )
        else if kvUnscoped != [ ] then
          throw (
            "gitleaks-allowlist-scope: the Cloudflare KV namespace allowlist lost "
            + "regexTarget = \"line\", so its regex is matched against the bare secret, never fires, "
            + "and silently stops suppressing anything (modules/development/gitleaks.nix)"
          )
        else
          pkgs.runCommandLocal "gitleaks-allowlist-scope-ok" { } ''
            echo "ok: no gitleaks allowlist path-scopes outside nixos-manual" > $out
          '';
    };
}

# A gitleaks allowlist entry under `paths` skips the whole file before its
# contents are scanned, so path-scoping a tree hides every real credential in
# it, not just the false positive the entry was added for. Measured with
# gitleaks 8.30.1: allowlisting secrets/private-ops/.* dropped the scan of that
# file to 0 bytes and a planted Stripe live key and Slack bot token in it both
# went undetected. Entries are compiled as unanchored regexes, so a pattern
# neither has to name the tree it reaches ("private-ops/.*" skips the same file)
# nor stop at one tree ("nixos-manual/.*|secrets/.*" reaches both). The guard is
# therefore an exact-match allowlist: only the two reviewed nixos-manual
# patterns may path-scope, and every other false positive is scoped by content.
# throw, not a failing derivation: `nix flake check --no-build` evaluates check
# attrs but never builds them, so only an eval-time failure gates the runs that
# use it (update-flake.yml, and check.yml on manual dispatch).
{ lib, ... }:
{
  perSystem =
    { config, pkgs, ... }:
    let
      # Structural parse rather than string splitting, because `paths=[` without
      # spaces, a reordered key, or an inline table all defeat an infix search,
      # and a guard that a whitespace change disarms is not a guard. gitleaks
      # honours the singular [allowlist] table and rule-scoped allowlists as
      # well, so fold both in; cfg.rules is absent while the config only extends
      # the default ruleset, which makes that term inert until a rule is added.
      allowlistsIn =
        text:
        let
          cfg = builtins.fromTOML text;
          tablesOf = t: (t.allowlists or [ ]) ++ lib.optional (t ? allowlist) t.allowlist;
        in
        tablesOf cfg ++ lib.concatMap tablesOf (cfg.rules or [ ]);

      # Both the definition a human edits and the artifact gitleaks actually
      # reads. Parsing only the source misses a direct .gitleaks.toml edit and
      # parsing only the artifact misses a source edit that skipped write-files;
      # managed-files-drift closes neither gap here, being a pre-commit hook
      # rather than a CI gate.
      allowlists =
        allowlistsIn config.files.file.".gitleaks.toml".text
        ++ allowlistsIn (builtins.readFile ../../.gitleaks.toml);

      reviewedPaths = [
        "nixos-manual/.*"
        "docs/nixos-manual/.*"
      ];

      unreviewedPathScope = lib.filter (
        a: lib.any (p: !lib.elem p reviewedPaths) (a.paths or [ ])
      ) allowlists;

      # The Cloudflare KV allowlist is a no-op unless it is line-scoped: against
      # the default target the regex is matched on the bare hex secret and never
      # sees the surrounding "keys KV:" text.
      kvBlocks = lib.filter (a: lib.any (lib.hasInfix "keys KV") (a.regexes or [ ])) allowlists;
      kvUnscoped = lib.filter (a: (a.regexTarget or "secret") != "line") kvBlocks;

      describe =
        entries: lib.concatStringsSep ", " (lib.unique (map (a: a.description or "<undescribed>") entries));
    in
    {
      checks.gitleaks-allowlist-scope =
        if unreviewedPathScope != [ ] then
          throw (
            "gitleaks-allowlist-scope: allowlist ${describe unreviewedPathScope} carries a paths entry "
            + "outside the reviewed set ${lib.concatStringsSep ", " reviewedPaths}. A paths entry makes "
            + "gitleaks skip those files entirely, hiding real leaks in them, and entries are unanchored "
            + "regexes so one can reach a tree it does not name. Scope by content with "
            + "regexTarget = \"line\" instead, or widen reviewedPaths deliberately "
            + "(modules/development/gitleaks.nix)"
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
            echo "ok: every gitleaks allowlist path entry is in the reviewed set" > $out
          '';
    };
}

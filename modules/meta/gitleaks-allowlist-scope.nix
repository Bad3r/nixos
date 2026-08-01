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
# [extend] is covered too, because it suppresses more broadly than any paths
# entry: disabledRules silences a rule across the whole repo and
# useDefault = false drops the default ruleset outright.
# throw, not a failing derivation: nothing builds check outputs. Every run that
# evaluates this forces drvPaths only (`nix eval --apply ... .drvPath`, used in
# place of `nix flake check --no-build` because Lix forces read-only store mode
# there), so an eval-time failure is the only thing that gates them: check.yml's
# eval-checks job on same-repo pull requests, check-compliance on manual
# dispatch, and update-flake.yml.
{ lib, ... }:
{
  perSystem =
    { config, pkgs, ... }:
    let
      # Both the definition a human edits and the artifact gitleaks actually
      # reads. Parsing only the source misses a direct .gitleaks.toml edit and
      # parsing only the artifact misses a source edit that skipped write-files;
      # managed-files-drift closes neither gap here, being a pre-commit hook
      # rather than a CI gate. Each entry keeps its origin so a throw names the
      # file that carries it rather than the one a reader would expect.
      sources = [
        {
          origin = "modules/development/gitleaks.nix";
          text = config.files.file.".gitleaks.toml".text;
        }
        {
          origin = ".gitleaks.toml";
          text = builtins.readFile ../../.gitleaks.toml;
        }
      ];

      # Structural parse rather than string splitting, because `paths=[` without
      # spaces, a reordered key, or an inline table all defeat an infix search,
      # and a guard that a whitespace change disarms is not a guard.
      parsed = map (s: s // { cfg = builtins.fromTOML s.text; }) sources;

      # gitleaks honours the singular [allowlist] table and rule-scoped
      # allowlists as well; cfg.rules is absent while the config only extends the
      # default ruleset, which makes that term inert until a rule is added.
      tablesOf = t: (t.allowlists or [ ]) ++ lib.optional (t ? allowlist) t.allowlist;

      allowlists = lib.concatMap (
        p:
        map (a: a // { inherit (p) origin; }) (
          tablesOf p.cfg ++ lib.concatMap tablesOf (p.cfg.rules or [ ])
        )
      ) parsed;

      reviewedPaths = [
        "nixos-manual/.*"
        "docs/nixos-manual/.*"
      ];

      # gitleaks keeps a default rule only when no local rule claims its id, so a
      # local [[rules]] entry reusing a default id with an unmatchable regex
      # replaces that detector across the whole repository while useDefault stays
      # true, disabledRules stays empty and no paths entry appears. Verified
      # against 8.30.1 with id = "generic-api-key" and regex = '$^': every other
      # branch here passed and the vault note reported nothing. Empty today,
      # because the config only extends the default ruleset.
      reviewedRuleIds = [ ];

      unreviewedRules = lib.filter (r: !lib.elem (r.id or "<unnamed>") reviewedRuleIds) (
        lib.concatMap (p: map (r: r // { inherit (p) origin; }) (p.cfg.rules or [ ])) parsed
      );

      unreviewedPathScope = lib.filter (
        a: lib.any (p: !lib.elem p reviewedPaths) (a.paths or [ ])
      ) allowlists;

      weakenedExtend = lib.filter (
        p:
        let
          e = p.cfg.extend or { };
        in
        (e.useDefault or false) != true || (e.disabledRules or [ ]) != [ ]
      ) parsed;

      # Every allowlist regex is pinned, not just the KV one. An allowlist regex
      # is matched against every finding in the repository, so a broad one
      # silences rules everywhere: verified against 8.30.1 that a global
      # [[allowlists]] with regexTarget = "line" and regexes = ["."] matches
      # every non-empty line and hides even a planted Stripe live key, which is
      # broader than the disabledRules case the [extend] branch bans and needs no
      # paths key to get there. Widening this is a deliberate edit here.
      reviewedRegexes = [
        "RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3"
        "(production|preview) keys KV: [0-9a-f]{32}"
      ];

      unreviewedRegexes = lib.filter (
        a: lib.any (r: !lib.elem r reviewedRegexes) (a.regexes or [ ])
      ) allowlists;

      # The Cloudflare KV allowlist is a no-op unless it is line-scoped: against
      # the default target the regex is matched on the bare hex secret and never
      # sees the surrounding "keys KV:" text.
      kvBlocks = lib.filter (a: lib.any (lib.hasInfix "keys KV") (a.regexes or [ ])) allowlists;
      kvUnscoped = lib.filter (a: (a.regexTarget or "secret") != "line") kvBlocks;

      bothFiles = lib.concatStringsSep " or " (map (s: s.origin) sources);
      describe =
        entries:
        lib.concatStringsSep ", " (
          lib.unique (map (a: "${a.origin}: ${a.description or "<undescribed>"}") entries)
        );
    in
    {
      checks.gitleaks-allowlist-scope =
        if unreviewedPathScope != [ ] then
          throw (
            "gitleaks-allowlist-scope: allowlist ${describe unreviewedPathScope} carries a paths entry "
            + "outside the reviewed set ${lib.concatStringsSep ", " reviewedPaths}. A paths entry makes "
            + "gitleaks skip those files entirely, hiding real leaks in them, and entries are unanchored "
            + "regexes so one can reach a tree it does not name. Scope by content with "
            + "regexTarget = \"line\" instead, or widen reviewedPaths deliberately"
          )
        else if weakenedExtend != [ ] then
          throw (
            "gitleaks-allowlist-scope: [extend] in ${
              lib.concatStringsSep ", " (lib.unique (map (p: p.origin) weakenedExtend))
            } drops the default ruleset or disables rules "
            + "(useDefault must stay true, disabledRules must stay empty). That suppresses a rule across "
            + "the whole repository, which is broader than the path-scoping this check already bans. "
            + "Scope the false positive by content with regexTarget = \"line\" instead"
          )
        else if unreviewedRegexes != [ ] then
          throw (
            "gitleaks-allowlist-scope: allowlist ${describe unreviewedRegexes} carries a regex "
            + "outside the reviewed set. An allowlist regex is matched against every finding in the "
            + "repository, so a broad one silences rules everywhere rather than in one tree; add the "
            + "exact regex to reviewedRegexes deliberately"
          )
        else if unreviewedRules != [ ] then
          throw (
            "gitleaks-allowlist-scope: local [[rules]] ${
              lib.concatStringsSep ", " (map (r: "${r.origin}: ${r.id or "<unnamed>"}") unreviewedRules)
            } is not in the reviewed set. A local rule reusing a default rule id replaces that "
            + "detector everywhere, which is broader than the path-scoping this check bans; add the "
            + "id to reviewedRuleIds deliberately"
          )
        else if kvBlocks == [ ] then
          throw (
            "gitleaks-allowlist-scope: the Cloudflare KV namespace allowlist is gone from ${bothFiles}; "
            + "drop this check along with it"
          )
        else if kvUnscoped != [ ] then
          throw (
            "gitleaks-allowlist-scope: the Cloudflare KV namespace allowlist in "
            + "${describe kvUnscoped} lost regexTarget = \"line\", so its regex is matched against the "
            + "bare secret, never fires, and silently stops suppressing anything"
          )
        else
          pkgs.runCommandLocal "gitleaks-allowlist-scope-ok" { } ''
            echo "ok: every gitleaks allowlist path entry is in the reviewed set" > $out
          '';
    };
}

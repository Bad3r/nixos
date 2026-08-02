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
# check-compliance job, which the workflow-level pull_request trigger runs on
# every pull request and not only on dispatch, and update-flake.yml.
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

      # Pinned by key set, not only by value. [extend] also takes `path` and
      # `url`, which load rules and allowlists from a config neither parse here
      # reads. gitleaks 8.30.1 refuses `path` together with `useDefault`, and
      # `path` on its own trips the useDefault test below, but `url` with
      # useDefault = true is accepted and would otherwise pass every branch with
      # the suppressing config living outside the repository entirely. Requiring
      # the key set to be exactly these two also fails closed on a key a future
      # release adds.
      extendKeys = [
        "useDefault"
        "disabledRules"
      ];

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

      kvTargetRules = [ "generic-api-key" ];

      # targetRules values are bounded for every allowlist, not only for the KV
      # one through kvUntargeted. untargetedRegexScope rejects a non-default
      # regexTarget only while targetRules is empty, so naming any rule there
      # passes it, and the values were pinned nowhere else: regexTarget = "line"
      # plus targetRules = ["stripe-access-token"] on the reviewed DNSCrypt entry
      # passes all nine other branches and silences stripe-access-token on every
      # line carrying the minisign key text. Same shape as reviewedPaths,
      # reviewedRegexes and reviewedRuleIds.
      # Deliberately not an alias of kvTargetRules despite the equal value:
      # kvUntargeted tests the KV entry for exact equality with kvTargetRules, so
      # widening the repo-wide reviewed set through an alias would silently
      # change what that branch demands of the KV entry.
      reviewedTargetRules = [ "generic-api-key" ];

      bothFiles = lib.concatStringsSep " or " (map (s: s.origin) sources);
      describe =
        entries:
        lib.concatStringsSep ", " (
          lib.unique (map (a: "${a.origin}: ${a.description or "<undescribed>"}") entries)
        );

      # A function of the parsed configs rather than a closure over the two real
      # ones, so the branches can be driven by fixtures below. Returns the id and
      # message of the first branch to reject, or null when every branch passes.
      # The id is what makes the fixtures load-bearing: asserting only that some
      # branch rejected would let an earlier branch cover for a later one that
      # had stopped working.
      verdict =
        parsed:
        let
          # gitleaks honours the singular [allowlist] table and rule-scoped
          # allowlists as well; cfg.rules is absent while the config only extends
          # the default ruleset, which makes that term inert until a rule is
          # added.
          tablesOf = t: (t.allowlists or [ ]) ++ lib.optional (t ? allowlist) t.allowlist;

          allowlists = lib.concatMap (
            p:
            map (a: a // { inherit (p) origin; }) (
              tablesOf p.cfg ++ lib.concatMap tablesOf (p.cfg.rules or [ ])
            )
          ) parsed;

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
            (e.useDefault or false) != true
            || (e.disabledRules or [ ]) != [ ]
            || lib.subtractLists extendKeys (lib.attrNames e) != [ ]
          ) parsed;

          unreviewedRegexes = lib.filter (
            a: lib.any (r: !lib.elem r reviewedRegexes) (a.regexes or [ ])
          ) allowlists;

          # stopwords and commits are the remaining suppression fields on an
          # allowlist and neither is bounded by the branches above. A stopword is
          # a case-insensitive substring test against the secret, so ["a"]
          # silences nearly everything: verified against 8.30.1 that it hides a
          # planted Stripe live key with no paths, no regexes and no new table. A
          # commits entry drops every finding in that commit, which is what the
          # baselines are for. The config carries neither, so any entry is a
          # deliberate edit here.
          unreviewedSuppressors = lib.filter (
            a: (a.stopwords or [ ]) != [ ] || (a.commits or [ ]) != [ ]
          ) allowlists;

          # The Cloudflare KV allowlist is a no-op unless it is line-scoped:
          # against the default target the regex is matched on the bare hex
          # secret and never sees the surrounding "keys KV:" text.
          kvBlocks = lib.filter (a: lib.any (lib.hasInfix "keys KV") (a.regexes or [ ])) allowlists;
          kvUnscoped = lib.filter (a: (a.regexTarget or "secret") != "line") kvBlocks;

          # A global line-target allowlist is evaluated against every finding of
          # every rule, so without targetRules the KV entry hides any real
          # credential that shares a line with its text. That vector is triggered
          # by file content rather than config, so nothing else here can catch
          # it; pinning the scope is the only guard available.
          kvUntargeted = lib.filter (a: (a.targetRules or [ ]) != kvTargetRules) kvBlocks;

          # The same hazard for every other allowlist, bounded by the property
          # that causes it rather than by which entry or which target happens to
          # have it today. Any regexTarget other than the default "secret" makes
          # an allowlist match text outside the secret ("line" the whole line,
          # "match" the whole rule match), so an untargeted one suppresses every
          # rule wherever its text appears. Both are live on 8.30.1: an
          # untargeted match-target allowlist carrying "sk_live_" hides a Stripe
          # key that is otherwise reported. Adding either target to the DNSCrypt
          # entry trips nothing else here, since its regex is already in
          # reviewedRegexes and it holds no "keys KV" text for kvBlocks. Testing
          # != "secret" also fails closed on a target a future gitleaks release
          # adds.
          untargetedRegexScope = lib.filter (
            a: (a.regexTarget or "secret") != "secret" && (a.targetRules or [ ]) == [ ]
          ) allowlists;

          unreviewedTargetRules = lib.filter (
            a: lib.any (r: !lib.elem r reviewedTargetRules) (a.targetRules or [ ])
          ) allowlists;

          # Which entries may reach outside the secret at all, not only which
          # rules they may name. The two branches above are each escapable by
          # satisfying the other: a non-default regexTarget is rejected only
          # while targetRules is empty, and targetRules values are checked only
          # against the reviewed set, so regexTarget = "line" plus
          # targetRules = ["generic-api-key"] on the DNSCrypt entry clears both
          # at once and silences generic-api-key, the rule that allowlist exists
          # for, on every line carrying the minisign key text. The KV entry is
          # the only one reviewed to match outside the secret, and kvUntargeted
          # and kvUnscoped already pin its target and its rule.
          unreviewedRegexScope = lib.filter (
            a: (a.regexTarget or "secret") != "secret" && !(lib.elem a kvBlocks)
          ) allowlists;
        in
        if unreviewedPathScope != [ ] then
          {
            id = "path-scope";
            message =
              "gitleaks-allowlist-scope: allowlist ${describe unreviewedPathScope} carries a paths entry "
              + "outside the reviewed set ${lib.concatStringsSep ", " reviewedPaths}. A paths entry makes "
              + "gitleaks skip those files entirely, hiding real leaks in them, and entries are unanchored "
              + "regexes so one can reach a tree it does not name. Scope by content with "
              + "regexTarget = \"line\" instead, or widen reviewedPaths deliberately";
          }
        else if weakenedExtend != [ ] then
          {
            id = "extend";
            message =
              "gitleaks-allowlist-scope: [extend] in ${
                lib.concatStringsSep ", " (lib.unique (map (p: p.origin) weakenedExtend))
              } drops the default ruleset, disables rules, or carries a key outside "
              + "${lib.concatStringsSep ", " extendKeys} (useDefault must stay true, disabledRules must "
              + "stay empty, and path or url would load rules and allowlists from a config this check "
              + "never reads). That suppresses rules across the whole repository, which is broader than "
              + "the path-scoping this check already bans. Scope the false positive by content with "
              + "regexTarget = \"line\" instead";
          }
        else if unreviewedRegexes != [ ] then
          {
            id = "regex";
            message =
              "gitleaks-allowlist-scope: allowlist ${describe unreviewedRegexes} carries a regex "
              + "outside the reviewed set. An allowlist regex is matched against every finding in the "
              + "repository, so a broad one silences rules everywhere rather than in one tree; add the "
              + "exact regex to reviewedRegexes deliberately";
          }
        else if unreviewedSuppressors != [ ] then
          {
            id = "suppressors";
            message =
              "gitleaks-allowlist-scope: allowlist ${describe unreviewedSuppressors} carries stopwords "
              + "or commits. A stopword is a case-insensitive substring test against every secret and a "
              + "commits entry drops every finding in that commit, so both suppress far more broadly "
              + "than the path-scoping this check bans; scope by content with regexTarget = \"line\", "
              + "or record the finding in the matching baseline instead";
          }
        else if unreviewedRules != [ ] then
          {
            id = "local-rule";
            message =
              "gitleaks-allowlist-scope: local [[rules]] ${
                lib.concatStringsSep ", " (map (r: "${r.origin}: ${r.id or "<unnamed>"}") unreviewedRules)
              } is not in the reviewed set. A local rule reusing a default rule id replaces that "
              + "detector everywhere, which is broader than the path-scoping this check bans; add the "
              + "id to reviewedRuleIds deliberately";
          }
        else if kvBlocks == [ ] then
          {
            id = "kv-missing";
            message =
              "gitleaks-allowlist-scope: the Cloudflare KV namespace allowlist is gone from ${bothFiles}; "
              + "drop this check along with it";
          }
        else if untargetedRegexScope != [ ] then
          {
            id = "untargeted-scope";
            message =
              "gitleaks-allowlist-scope: allowlist ${describe untargetedRegexScope} sets regexTarget "
              + "with no targetRules. Any target other than the default secret is matched against text "
              + "outside the secret, so an untargeted one suppresses every rule's findings wherever its "
              + "text appears; name the rule it is meant to silence in targetRules";
          }
        else if kvUntargeted != [ ] then
          {
            id = "kv-untargeted";
            message =
              "gitleaks-allowlist-scope: the Cloudflare KV namespace allowlist in "
              + "${describe kvUntargeted} is not scoped to ${lib.concatStringsSep ", " kvTargetRules}. "
              + "A global line-target allowlist is matched against every rule's findings, so it would "
              + "suppress any real credential sharing a line with the KV text";
          }
        else if kvUnscoped != [ ] then
          {
            id = "kv-unscoped";
            message =
              "gitleaks-allowlist-scope: the Cloudflare KV namespace allowlist in "
              + "${describe kvUnscoped} lost regexTarget = \"line\", so its regex is matched against the "
              + "bare secret, never fires, and silently stops suppressing anything";
          }
        # Last, after kv-untargeted: that branch's fixture names a rule outside
        # the reviewed set to get past untargeted-scope, so an earlier placement
        # here would reject it first and mask the branch it exists to cover.
        else if unreviewedTargetRules != [ ] then
          {
            id = "target-rules";
            message =
              "gitleaks-allowlist-scope: allowlist ${describe unreviewedTargetRules} targets a rule "
              + "outside the reviewed set ${lib.concatStringsSep ", " reviewedTargetRules}. A "
              + "non-default regexTarget matches text outside the secret, so naming a rule here "
              + "silences that rule wherever the allowlist text appears; add the rule id to "
              + "reviewedTargetRules deliberately";
          }
        # Last, after target-rules: the untargeted-scope and target-rules
        # fixtures are both non-KV entries carrying a non-default regexTarget, so
        # any earlier placement rejects them here first and masks both branches.
        else if unreviewedRegexScope != [ ] then
          {
            id = "regex-scope";
            message =
              "gitleaks-allowlist-scope: allowlist ${describe unreviewedRegexScope} sets a non-default "
              + "regexTarget outside the Cloudflare KV entry, which is the only one reviewed to match "
              + "off the secret. Any other target makes the entry match text the credential does not "
              + "contain, so it suppresses its targeted rules wherever that text appears; scope the "
              + "false positive against the secret instead";
          }
        else
          null;

      real = map (s: s // { cfg = builtins.fromTOML s.text; }) sources;
      realVerdict = verdict real;

      # One synthetic config per branch, each the reviewed config with a single
      # field perturbed, so a branch that stops rejecting its own bypass fails on
      # the pull request that narrows it. Every guard this check has carried was
      # verified once by hand-editing the real config, running write-files and
      # reverting, and four of them (hasInfix "secrets", hasInfix "nixos-manual",
      # the entry-scoped targetRules test, the regexTarget == "line" test) were
      # later found bypassable anyway; a procedure that re-runs on nobody's
      # machine cannot catch that.
      #
      # Each fixture must reach its own branch, so it has to pass every earlier
      # one: kv-untargeted names a rule other than generic-api-key rather than
      # dropping targetRules, because an empty targetRules trips untargeted-scope
      # first, and kv-unscoped keeps targetRules so it reaches the last branch.
      fixture = toml: [
        {
          origin = "fixture";
          cfg = builtins.fromTOML toml;
        }
      ];

      okAllowlists = ''
        [[allowlists]]
        description = "docs"
        paths = ["nixos-manual/.*", "docs/nixos-manual/.*"]

        [[allowlists]]
        description = "dnscrypt"
        regexes = ["RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3"]
      '';

      okKv = ''
        [[allowlists]]
        description = "kv"
        regexTarget = "line"
        targetRules = ["generic-api-key"]
        regexes = ["(production|preview) keys KV: [0-9a-f]{32}"]
      '';

      okExtend = ''
        [extend]
        useDefault = true
      '';

      cases = [
        {
          id = "path-scope";
          toml = ''
            ${okExtend}
            ${okKv}
            [[allowlists]]
            description = "reaches a tree it does not name"
            paths = ["private-ops/.*"]
          '';
        }
        {
          id = "extend";
          toml = ''
            [extend]
            useDefault = true
            url = "https://example.invalid/rules.toml"
            ${okAllowlists}
            ${okKv}
          '';
        }
        {
          id = "regex";
          toml = ''
            ${okExtend}
            ${okAllowlists}
            ${okKv}
            [[allowlists]]
            description = "matches every secret"
            regexes = ["."]
          '';
        }
        {
          id = "suppressors";
          toml = ''
            ${okExtend}
            ${okAllowlists}
            ${okKv}
            [[allowlists]]
            description = "substring test against every secret"
            stopwords = ["a"]
          '';
        }
        {
          id = "local-rule";
          toml = ''
            ${okExtend}
            ${okAllowlists}
            ${okKv}
            [[rules]]
            id = "generic-api-key"
            description = "shadows the default detector"
            regex = "$^"
          '';
        }
        {
          id = "kv-missing";
          toml = ''
            ${okExtend}
            ${okAllowlists}
          '';
        }
        {
          id = "untargeted-scope";
          toml = ''
            ${okExtend}
            ${okKv}
            [[allowlists]]
            description = "match-target with no targetRules"
            regexTarget = "match"
            regexes = ["RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3"]
          '';
        }
        {
          id = "kv-untargeted";
          toml = ''
            ${okExtend}
            ${okAllowlists}
            [[allowlists]]
            description = "kv scoped to the wrong rule"
            regexTarget = "line"
            targetRules = ["stripe-access-token"]
            regexes = ["(production|preview) keys KV: [0-9a-f]{32}"]
          '';
        }
        {
          id = "kv-unscoped";
          toml = ''
            ${okExtend}
            ${okAllowlists}
            [[allowlists]]
            description = "kv matched against the bare secret"
            targetRules = ["generic-api-key"]
            regexes = ["(production|preview) keys KV: [0-9a-f]{32}"]
          '';
        }
        # The reviewed DNSCrypt entry with two keys added rather than one. Every
        # other branch passes it: no paths, [extend] untouched, its regex already
        # reviewed, no stopwords or commits, no local rule, kvBlocks still
        # present and still correctly targeted, and untargeted-scope skips it
        # because targetRules is non-empty. It silences stripe-access-token on
        # every line carrying the minisign key text.
        {
          id = "target-rules";
          toml = ''
            ${okExtend}
            ${okKv}
            [[allowlists]]
            description = "reviewed regex aimed at an unreviewed rule"
            regexTarget = "line"
            targetRules = ["stripe-access-token"]
            regexes = ["RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3"]
          '';
        }
        # Everything reviewed taken one at a time: reviewed regex, reviewed
        # target rule, and the two branches above each satisfied by what clears
        # the other. Only the entry's identity is left to reject it on.
        {
          id = "regex-scope";
          toml = ''
            ${okExtend}
            ${okKv}
            [[allowlists]]
            description = "reviewed regex and reviewed rule, matched off the secret"
            regexTarget = "line"
            targetRules = ["generic-api-key"]
            regexes = ["RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3"]
          '';
        }
      ];

      caseResult =
        c:
        let
          v = verdict (fixture c.toml);
        in
        if v == null then "nothing" else v.id;

      missed = lib.filter (c: caseResult c != c.id) cases;
    in
    {
      checks.gitleaks-allowlist-scope =
        if realVerdict != null then
          throw realVerdict.message
        else if missed != [ ] then
          throw (
            "gitleaks-allowlist-scope: the branch a bypass is meant to trip no longer rejects it: ${
              lib.concatStringsSep ", " (map (c: "${c.id} fixture rejected by ${caseResult c}") missed)
            }. Either the branch was narrowed and now misses the case it was added for, or an earlier "
            + "branch changed and is masking it; fix the branch rather than the fixture"
          )
        else
          pkgs.runCommandLocal "gitleaks-allowlist-scope-ok" { } ''
            echo "ok: every gitleaks allowlist path entry is in the reviewed set" > $out
          '';
    };
}

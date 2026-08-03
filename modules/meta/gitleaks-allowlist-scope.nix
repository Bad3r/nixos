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
      # reviewedPaths is per source, not global: a paths pattern is matched
      # against a File rooted at the tree being scanned, and the submodule pass
      # scans secrets/, where File comes back submodule-relative. The two
      # documentation patterns are superproject trees, so the config that governs
      # the submodule pass may carry no paths entry at all and its reviewed set
      # is empty.
      superprojectPaths = [
        "^nixos-manual/"
        "^docs/nixos-manual/"
      ];

      managedConfigs = [
        {
          file = ".gitleaks.toml";
          reviewedPaths = superprojectPaths;
          kvAllowed = false;
        }
        {
          file = ".gitleaks-secrets.toml";
          reviewedPaths = [ ];
          kvAllowed = true;
        }
        {
          file = ".gitleaks-gitlink.toml";
          reviewedPaths = [ ];
          kvAllowed = false;
        }
      ];

      sources = lib.concatMap (c: [
        {
          origin = "modules/development/gitleaks.nix (${c.file})";
          text = config.files.file.${c.file}.text;
          inherit (c) file reviewedPaths kvAllowed;
        }
        {
          origin = c.file;
          text = builtins.readFile (lib.path.append ../.. c.file);
          inherit (c) file reviewedPaths kvAllowed;
        }
      ]) managedConfigs;

      # Quantified over the files write-files actually emits, not over
      # managedConfigs: reviewedSources is derived from the same list, so
      # subtracting one from the other is empty for every possible value and
      # dropping a contract removes it from both at once. Keyed on the file name
      # so a new .gitleaks-*.toml has to gain a contract here before it can be
      # scanned with, and removing a contract while the file still ships throws.
      managedGitleaksFiles = lib.filter (n: lib.hasPrefix ".gitleaks" n && lib.hasSuffix ".toml" n) (
        lib.attrNames config.files.file
      );

      managedConfigCoverage = configs: lib.subtractLists (map (c: c.file) configs) managedGitleaksFiles;

      unjudgedSources = map (file: { origin = file; }) (managedConfigCoverage managedConfigs);

      managedConfigCases = [
        {
          id = "all-managed";
          configs = managedConfigs;
          expected = [ ];
        }
        {
          id = "missing-secrets-contract";
          configs = lib.filter (c: c.file != ".gitleaks-secrets.toml") managedConfigs;
          expected = [ ".gitleaks-secrets.toml" ];
        }
      ];

      missedManagedConfigCases = lib.filter (
        c: managedConfigCoverage c.configs != c.expected
      ) managedConfigCases;

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
        "usedefault"
        "disabledrules"
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
            map (a: a // { inherit (p) origin reviewedPaths kvAllowed; }) (
              tablesOf p.cfg ++ lib.concatMap tablesOf (p.cfg.rules or [ ])
            )
          ) parsed;

          unreviewedRules = lib.filter (r: !lib.elem (r.id or "<unnamed>") reviewedRuleIds) (
            lib.concatMap (p: map (r: r // { inherit (p) origin; }) (p.cfg.rules or [ ])) parsed
          );

          unreviewedPathScope = lib.filter (
            a: lib.any (p: !lib.elem p a.reviewedPaths) (a.paths or [ ])
          ) allowlists;

          weakenedExtend = lib.filter (
            p:
            let
              e = p.cfg.extend or { };
            in
            (e.usedefault or false) != true
            || (e.disabledrules or [ ]) != [ ]
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

          # Pinned by key set as well as by value, for the reason extendKeys
          # gives. The branches here enumerate the suppression fields gitleaks
          # 8.30.1 has, and every one of them was added only after review found
          # it being a live bypass: stopwords and commits, then targetRules. A
          # field a future release adds would pass all of them, and `condition`
          # already exists unlisted on 8.30.1, where it switches an allowlist
          # from OR to AND across its own fields. origin is injected above, not a
          # config key.
          allowlistKeys = [
            "origin"
            "reviewedPaths"
            "kvAllowed"
            "description"
            "paths"
            "regexes"
            "regextarget"
            "targetrules"
            "stopwords"
            "commits"
            "condition"
          ];

          unknownAllowlistKeys = lib.filter (
            a: lib.subtractLists allowlistKeys (lib.attrNames a) != [ ]
          ) allowlists;

          # The Cloudflare KV allowlist is a no-op unless it is line-scoped:
          # against the default target the regex is matched on the bare hex
          # secret and never sees the surrounding "keys KV:" text.
          kvBlocks = lib.filter (a: lib.any (lib.hasInfix "keys KV") (a.regexes or [ ])) allowlists;

          # The KV note exists only in the private submodule, so its allowlist is
          # permitted only in the two sources governing that pass. Check both
          # directions: a missing private entry breaks the false-positive fix,
          # while an unexpected superproject entry creates a suppression channel
          # for public files that the note does not justify.
          kvMissingIn = lib.filter (p: p.kvAllowed && !lib.any (a: a.origin == p.origin) kvBlocks) parsed;
          kvUnexpectedIn = lib.filter (p: !p.kvAllowed && lib.any (a: a.origin == p.origin) kvBlocks) parsed;
          kvUnscoped = lib.filter (a: (a.regextarget or "secret") != "line") kvBlocks;

          # A global line-target allowlist is evaluated against every finding of
          # every rule, so without targetRules the KV entry hides any real
          # credential that shares a line with its text. That vector is triggered
          # by file content rather than config, so nothing else here can catch
          # it; pinning the scope is the only guard available.
          kvUntargeted = lib.filter (a: (a.targetrules or [ ]) != kvTargetRules) kvBlocks;

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
            a: (a.regextarget or "secret") != "secret" && (a.targetrules or [ ]) == [ ]
          ) allowlists;

          unreviewedTargetRules = lib.filter (
            a: lib.any (r: !lib.elem r reviewedTargetRules) (a.targetrules or [ ])
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
          # Exempt by exact regex list, not by kvBlocks membership: kvBlocks is an
          # infix test over one regex, so an entry carrying the KV regex
          # alongside another reviewed regex inherits the exemption and matches
          # off the secret for that text too. Appending the KV regex to the
          # DNSCrypt entry, with regexTarget and targetRules, otherwise clears
          # every branch while silencing generic-api-key on every line holding
          # the minisign key. Derived from reviewedRegexes so the pattern is not
          # duplicated here.
          kvExact = lib.filter (
            a: (a.regexes or [ ]) == lib.filter (lib.hasInfix "keys KV") reviewedRegexes
          ) kvBlocks;

          unreviewedRegexScope = lib.filter (
            a: (a.regextarget or "secret") != "secret" && !(lib.elem a kvExact)
          ) allowlists;
        in
        if unknownAllowlistKeys != [ ] then
          {
            id = "allowlist-keys";
            message =
              "gitleaks-allowlist-scope: allowlist ${describe unknownAllowlistKeys} carries a key "
              + "outside ${lib.concatStringsSep ", " allowlistKeys}. Every field bounded above was "
              + "added after it was found to suppress findings, so an unrecognised one is an "
              + "unreviewed suppression channel; bound it here before allowing it";
          }
        else if unreviewedPathScope != [ ] then
          {
            id = "path-scope";
            message =
              "gitleaks-allowlist-scope: allowlist ${describe unreviewedPathScope} carries a paths entry "
              + "outside the reviewed set for its file (${
                let
                  reviewed = lib.unique (lib.concatMap (a: a.reviewedPaths) unreviewedPathScope);
                in
                if reviewed == [ ] then "none permitted in this file" else lib.concatStringsSep ", " reviewed
              }). A paths entry makes "
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
        else if kvUnexpectedIn != [ ] then
          {
            id = "kv-unexpected";
            message =
              "gitleaks-allowlist-scope: the Cloudflare KV namespace allowlist is present in "
              + "${lib.concatStringsSep ", " (map (p: p.origin) kvUnexpectedIn)} even though those "
              + "sources scan public superproject files. Keep this content-scoped suppression in the "
              + "two .gitleaks-secrets.toml sources that scan the private operational note";
          }
        else if kvMissingIn != [ ] then
          {
            id = "kv-missing";
            message =
              "gitleaks-allowlist-scope: the Cloudflare KV namespace allowlist is gone from ${
                lib.concatStringsSep ", " (map (p: p.origin) kvMissingIn)
              }. The entry belongs in the .gitleaks-secrets.toml sources because the note it exists for "
              + "is scanned only through the private submodule pass";
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

      # gitleaks reads its config through viper, which lowercases every key
      # before mapstructure decodes it, so Paths, RegexTarget and [[Allowlists]]
      # are all honoured while builtins.fromTOML keeps the spelling verbatim.
      # Verified on 8.30.1: a capital [[Allowlists]] table, and a capital Paths
      # key under the lowercase table, each suppress a github-pat the defaults
      # report. Folding the case here rather than at each lookup is what keeps a
      # single capital letter from hiding an entry from every branch at once.
      # Values are left alone: a capitalised "Line" fails the equality tests
      # below rather than passing them, so it fails closed.
      # Collisions are refused rather than folded. TOML keys are case-sensitive,
      # so one table may carry both spellings, and mapAttrs' is listToAttrs over
      # attrNames, which keeps the first: attrNames sorts "Paths" before "paths"
      # (0x50 < 0x70), so a reviewed Paths would survive and a malicious
      # lowercase paths would be discarded before any branch saw it. gitleaks
      # resolves the same table through viper's insensitiviseMap, which deletes
      # and re-inserts each key while ranging over a Go map, so which value
      # survives there is iteration-order dependent. No fold can pick the same
      # winner the scanner will, which makes refusing the only sound option.
      # Throws in the parse rather than returning a verdict id, so `cases` cannot
      # reach it; collisionCases below drives it through tryEval instead.
      # Origin-carrying like every verdict message, because lowerKeys runs over
      # all managed source and artifact entries: a collision present only in the
      # artifact would otherwise send the reader to modules/development/gitleaks.nix, where the entry is
      # absent, and the artifact-only edit is the direction this check was
      # extended to cover in the first place.
      lowerKeys =
        origin: v:
        if lib.isAttrs v then
          let
            names = lib.attrNames v;
          in
          if builtins.length (lib.unique (map lib.toLower names)) != builtins.length names then
            throw (
              "gitleaks-allowlist-scope: ${origin} carries a table with keys differing only in "
              + "case (${lib.concatStringsSep ", " names}). gitleaks folds them to one key through "
              + "viper and which value survives is iteration-order dependent, so no branch here "
              + "can be trusted to have inspected the one in effect; spell each key once"
            )
          else
            lib.mapAttrs' (n: x: lib.nameValuePair (lib.toLower n) (lowerKeys origin x)) v
        else if lib.isList v then
          map (lowerKeys origin) v
        else
          v;

      real = map (s: s // { cfg = lowerKeys s.origin (builtins.fromTOML s.text); }) sources;
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
      # Takes the case, not just its toml, so a case can drive the empty reviewed
      # set that .gitleaks-secrets.toml carries. Hardcoding superprojectPaths
      # here left the per-source split asserted by nothing: reverting it to a
      # single global binding kept every fixture green, because the real submodule
      # config happens to carry no paths key.
      # A case may supply several sources through `tomls`. kvMissingIn is the one
      # predicate that quantifies across them, and a single-source fixture cannot
      # tell it apart from the global existence test it replaced: the kv-missing
      # case carries no KV block at all, so kvBlocks is empty under both
      # spellings and both return kv-missing.
      fixture =
        c:
        lib.imap0 (
          i: toml:
          let
            origin = "fixture-${toString i}";
          in
          {
            inherit origin;
            reviewedPaths = c.reviewedPaths or superprojectPaths;
            kvAllowed = c.kvAllowed or true;
            cfg = lowerKeys origin (builtins.fromTOML toml);
          }
        ) (c.tomls or [ c.toml ]);

      okAllowlists = ''
        [[allowlists]]
        description = "docs"
        paths = ["^nixos-manual/", "^docs/nixos-manual/"]

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
        # First, matching the branch order: an unrecognised field is bounded by
        # nothing else, so a later placement would let any enumerated branch mask
        # it. The key is deliberately not `condition`, which is enumerated: this
        # stands in for the field a future release adds, which is the case the
        # branch exists for.
        {
          id = "allowlist-keys";
          toml = ''
            ${okExtend}
            ${okAllowlists}
            ${okKv}
            [[allowlists]]
            description = "field this check does not enumerate"
            unreviewedSuppressionField = ["anything"]
          '';
        }
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
        # The reviewed superproject scope, in a source whose reviewed set is
        # empty. Only the per-source split rejects this: with reviewedPaths
        # global again it is the approved pattern and passes.
        {
          id = "path-scope";
          reviewedPaths = [ ];
          toml = ''
            ${okExtend}
            ${okKv}
            [[allowlists]]
            description = "superproject documentation scope in the submodule config"
            paths = ["^nixos-manual/"]
          '';
        }
        # The singular table gitleaks still accepts, and a rule-scoped allowlist.
        # Both are folded in by tablesOf and neither is reachable through a
        # top-level [[allowlists]], so dropping either fold is otherwise
        # invisible here. Both land on path-scope, the first branch, so the rule
        # in the second does not reach unreviewedRules.
        {
          id = "path-scope";
          toml = ''
            ${okExtend}
            ${okKv}
            [allowlist]
            description = "path-scoped through the singular table"
            paths = ["private-ops/.*"]
          '';
        }
        {
          id = "path-scope";
          toml = ''
            ${okExtend}
            ${okKv}
            [[rules]]
            id = "fixture-rule"
            description = "carries a rule-scoped allowlist"
            regex = "$^"
            [[rules.allowlists]]
            description = "path-scoped under a rule"
            paths = ["private-ops/.*"]
          '';
        }
        # The same entry with the capitalisation viper accepts and fromTOML does
        # not fold, in both the table name and the key. Fails the moment
        # lowerKeys stops normalising either one. No lowercase allowlist table
        # here on purpose: mixing spellings is the collision lowerKeys refuses
        # outright, which would mask this case behind a parse error.
        {
          id = "path-scope";
          toml = ''
            ${okExtend}
            [[Allowlists]]
            description = "path-scoped through a capital letter"
            Paths = ["private-ops/.*"]
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
        # weakenedExtend is a three-way disjunction and missed proves only that
        # the branch is reachable. These two carry the vectors measured live:
        # useDefault = false drops the ruleset outright, disabledRules silences a
        # rule repo-wide with the file still scanned.
        {
          id = "extend";
          toml = ''
            [extend]
            useDefault = false
            ${okAllowlists}
            ${okKv}
          '';
        }
        {
          id = "extend";
          toml = ''
            [extend]
            useDefault = true
            disabledRules = ["generic-api-key"]
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
        # The other disjunct: a commits entry drops every finding in that commit
        # from the history pass, which is what the reviewed baselines do, minus
        # the review.
        {
          id = "suppressors";
          toml = ''
            ${okExtend}
            ${okAllowlists}
            ${okKv}
            [[allowlists]]
            description = "drops every finding in a commit"
            commits = ["0000000000000000000000000000000000000000"]
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
          id = "kv-unexpected";
          kvAllowed = false;
          toml = ''
            ${okExtend}
            ${okAllowlists}
            ${okKv}
          '';
        }
        # Per source, not merely somewhere: one config keeping the KV block
        # satisfies a global existence test while the config governing the tree
        # the note lives in has lost it.
        {
          id = "kv-missing";
          tomls = [
            ''
              ${okExtend}
              ${okAllowlists}
              ${okKv}
            ''
            ''
              ${okExtend}
              ${okAllowlists}
            ''
          ];
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
        # The same reach taken by bundling rather than by adding a key: carrying
        # the KV regex makes the entry a kvBlock, which is what the exemption was
        # keyed on. Same id as the case above because both must be rejected by
        # the same branch; missed compares per case, so ids need not be unique.
        {
          id = "regex-scope";
          toml = ''
            ${okExtend}
            ${okAllowlists}
            [[allowlists]]
            description = "kv regex bundled with a second reviewed regex"
            regexTarget = "line"
            targetRules = ["generic-api-key"]
            regexes = [
              "(production|preview) keys KV: [0-9a-f]{32}",
              "RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3",
            ]
          '';
        }
      ];

      caseResult =
        c:
        let
          v = verdict (fixture c);
        in
        if v == null then "nothing" else v.id;

      missed = lib.filter (c: caseResult c != c.id) cases;

      # The collision refusal throws inside lowerKeys rather than returning a
      # verdict, so `cases` cannot reach it. throw is catchable, so tryEval
      # drives it the same way, and deepSeq forces the nested tables where a
      # collision actually fires: a top-level-only check, or `<` in place of
      # `!=`, leaves every other fixture green.
      collisionCases = [
        # Inside an allowlist table, which is the shape that bypasses the branches.
        ''
          ${okExtend}
          ${okKv}
          [[allowlists]]
          description = "one table, two spellings of the same key"
          Paths = ["nixos-manual/.*"]
          paths = ["secrets/.*"]
        ''
        # And at the top level, where the colliding tables are lists.
        ''
          ${okExtend}
          ${okKv}
          [[Allowlists]]
          description = "capital table beside the lowercase one"
          paths = ["private-ops/.*"]
        ''
      ];

      collisionsAccepted = lib.filter (
        toml:
        (builtins.tryEval (builtins.deepSeq (lowerKeys "fixture" (builtins.fromTOML toml)) true)).success
      ) collisionCases;
    in
    {
      checks.gitleaks-allowlist-scope =
        if unjudgedSources != [ ] then
          throw (
            "gitleaks-allowlist-scope: ${
              lib.concatStringsSep ", " (map (s: s.origin) unjudgedSources)
            } is no longer "
            + "judged by this check, so every suppression field in it is unbounded; restore it to "
            + "sources rather than narrowing reviewedSources"
          )
        else if missedManagedConfigCases != [ ] then
          throw (
            "gitleaks-allowlist-scope: managed config coverage fixture(s) no longer detect a missing contract: "
            + lib.concatStringsSep ", " (map (c: c.id) missedManagedConfigCases)
          )
        else if realVerdict != null then
          throw realVerdict.message
        else if collisionsAccepted != [ ] then
          throw (
            "gitleaks-allowlist-scope: lowerKeys accepted a table carrying keys that differ only in "
            + "case. gitleaks folds them through viper and which value survives is iteration-order "
            + "dependent, so every branch here may be inspecting the spelling that is not in effect"
          )
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

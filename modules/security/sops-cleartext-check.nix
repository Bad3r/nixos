# Regression gate for issue #344: any file under secrets/ that the .sops.yaml
# creation_rules mark as encryptable must actually carry the sops
# ENC[AES256_GCM, MAC token.
# The pre-commit ensure-sops hook only sees superproject staged files, so a
# cleartext commit made inside the secrets submodule bypasses it; this check
# scans the checked-out tree the flake actually ships.
#
# Scope: effective only where the secrets/ submodule content is checked out
# (local dev trees, git hooks). CI evaluates the secretless `path:.` checkout
# (issue #333, .github/workflows/check.yml) with no submodule content, so the
# scan is skipped there: a local defense-in-depth gate, not a CI-enforced
# invariant on the secrets gitlink. Initializing the submodule in CI is
# deliberately not done: Bad3r/secrets is private and the secretless-eval
# design keeps CI from fetching it.
{ lib, ... }:
let
  secretsDir = ../../secrets;
  # An absent or empty submodule is the secretless checkout used by CI
  # (see issue #333); scanning is only meaningful when content is present.
  secretsPresent = builtins.pathExists secretsDir && builtins.readDir secretsDir != { };

  # Literal mirrors of the non-explicit creation rules in
  # modules/security/sops-policy.nix. Reading the policy through
  # config.flake.lib recurses the flake-parts fixpoint, so the sync is enforced
  # below against the generated .sops.yaml instead.
  extAlternation = "yaml|yml|json|env|ini|asc|md|txt";
  # `(?i)` mirrors the case-insensitive catch-all emitted to .sops.yaml.
  # Line terminators prevent a narrowed replacement from satisfying an infix check.
  catchAllLine = "- path_regex: (?i)secrets/.*\\.(${extAlternation})$\n";
  fontsLine = "- path_regex: secrets/fonts/.+\n";
  extensionlessPathPattern = "(.*/)?[^/.]+$";
  extensionlessLine = "- path_regex: secrets/${extensionlessPathPattern}\n";
  sopsPolicy = builtins.readFile ../../.sops.yaml;
  ruleCount = builtins.length (
    lib.filter (line: lib.hasInfix "- path_regex:" line) (lib.splitString "\n" sopsPolicy)
  );
  policySynced =
    lib.hasInfix catchAllLine sopsPolicy
    && lib.hasInfix fontsLine sopsPolicy
    && lib.hasInfix extensionlessLine sopsPolicy
    # Three exact rules and three broad rules are currently generated. A new
    # creation rule must be mirrored in this check before the count changes.
    && ruleCount == 6;

  listFiles =
    dir: prefix:
    lib.concatLists (
      lib.mapAttrsToList (
        name: type:
        if type == "directory" then
          listFiles (dir + "/${name}") "${prefix}${name}/"
        else if type == "regular" then
          [ "${prefix}${name}" ]
        else
          [ ]
      ) (builtins.readDir dir)
    );

  # Mirrors the creation_rules surface: the extension catch-all, the fonts/
  # any-extension rule, and the extensionless-basename rule. The extension
  # match case-folds path to mirror the `(?i)` catch-all in .sops.yaml, so a
  # case-variant name (Runbook.MD) is still required-encrypted (#344).
  # Exemptions are the intentional cleartext conventions: *.example templates
  # and the local-decryption prefixes
  # (decrypted_*, *.dec.*), which the secrets submodule's own .gitignore
  # ignores and which reach evaluation through `path:` refs that copy
  # untracked files. Superproject ignore rules do not govern the submodule's
  # index, so these remain filename-level local exceptions, not encryption
  # guarantees for tracked submodule content.
  mustBeEncrypted =
    path:
    let
      base = baseNameOf path;
    in
    !(lib.hasSuffix ".example" path)
    && !(lib.hasPrefix "decrypted_" base)
    && !(lib.hasInfix ".dec." base)
    && (
      lib.hasPrefix "fonts/" path
      || builtins.match ".*\\.(${extAlternation})" (lib.toLower path) != null
      || builtins.match extensionlessPathPattern path != null
    );

  # lib.hasInfix is regex-based and overflows the evaluator stack on
  # megabyte-scale strings (std::regex recursion; the sops-encrypted font
  # blob is ~1 MiB), so scan each needle in bounded chunks with a needle-sized
  # overlap. SOPS 3.13.3 emits `lastmodified` metadata in every supported
  # encrypted format, using `sops_lastmodified` for dotenv, so requiring it
  # alongside the full cipher token rejects quoted-token cleartext samples.
  hasChunkedInfix =
    needle: s:
    let
      len = builtins.stringLength s;
      chunkSize = 8192;
      overlap = builtins.stringLength needle;
      pattern = ".*${lib.escapeRegex needle}.*";
      go =
        i:
        i < len
        && (
          builtins.match pattern (builtins.substring i (chunkSize + overlap) s) != null || go (i + chunkSize)
        );
    in
    go 0;

  hasSopsMarkers = s: (hasChunkedInfix "ENC[AES256_GCM," s) && (hasChunkedInfix "lastmodified" s);

  isCleartext =
    path:
    let
      content = builtins.readFile (secretsDir + "/${path}");
    in
    !(hasSopsMarkers content);

  cleartext =
    if secretsPresent then
      lib.filter isCleartext (lib.filter mustBeEncrypted (listFiles secretsDir ""))
    else
      [ ];
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.secrets-no-cleartext =
        # throw, not a failing derivation: CI evaluates check drvPaths with
        # --no-build, so only an eval-time failure gates it (same rationale
        # as modules/meta/ci-lix-parity.nix).
        if !policySynced then
          throw (
            "sops-cleartext-check.nix creation-rules mirror drifted from .sops.yaml "
            + "(rule count or pattern); update extAlternation, fontsLine, extensionlessLine, or ruleCount "
            + "to match modules/security/sops-policy.nix"
          )
        else if !secretsPresent then
          pkgs.runCommandLocal "secrets-no-cleartext-skipped" { } ''
            echo "skipped: secrets/ submodule content not present in this checkout" > $out
          ''
        else if cleartext != [ ] then
          throw (
            "secrets/ contains cleartext files matched by .sops.yaml creation_rules: "
            + lib.concatStringsSep ", " cleartext
            + ". Encrypt them with sops or rename them to a *.example template."
          )
        else
          pkgs.runCommandLocal "secrets-no-cleartext-ok" { } ''
            echo "ok: every creation_rules-matched file under secrets/ carries SOPS MAC and lastmodified markers" > $out
          '';
    };
}

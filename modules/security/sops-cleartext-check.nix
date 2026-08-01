# Regression gate for issue #344: any non-exempt file under secrets/ that the
# .sops.yaml creation_rules mark as encryptable must actually carry the sops
# ENC[AES256_GCM, MAC token.
# The pre-commit ensure-sops hook only sees superproject staged files, so a
# cleartext commit made inside the secrets submodule bypasses it. This check
# scans the checked-out tree the flake actually ships and its policy parity
# assertion is enforced by the compliance workflow.
#
# Scope: payload scanning is effective where the secrets/ submodule content is
# checked out, such as local development trees and git hooks. CI evaluates the
# secretless path:. checkout (issue #333, .github/workflows/check.yml), so the
# scan is skipped there while policy parity is still checked. Initializing the
# submodule in CI is deliberately not done: Bad3r/secrets is private and the
# secretless-eval design keeps CI from fetching it.
{ lib, ... }:
let
  secretsDir = ../../secrets;
  # An absent or empty submodule is the secretless checkout used by CI
  # (see issue #333); scanning is only meaningful when content is present.
  secretsPresent = builtins.pathExists secretsDir && builtins.readDir secretsDir != { };

  # Literal mirror of the deny-by-default creation rule in
  # modules/security/sops-policy.nix. Reading the policy through
  # config.flake.lib recurses the flake-parts fixpoint, so the sync is enforced
  # below against the generated .sops.yaml instead.
  # The final rule must remain last because SOPS applies the first matching
  # creation rule. The line is checked as a suffix of the extracted rule
  # pattern, so a narrowed replacement cannot satisfy the parity assertion.
  defaultRuleLine = "- path_regex: secrets/.*";
  # act.yaml is the only rule that leaves selected fields cleartext inside an
  # otherwise encrypted file. A SOPS footer cannot detect field-level drift.
  actEncryptedRegexLine = ''encrypted_regex: "^(github_token)$"'';
  sopsPolicy = builtins.readFile ../../.sops.yaml;
  rulePatterns = lib.filter (line: lib.hasInfix "- path_regex:" line) (
    lib.splitString "\n" sopsPolicy
  );
  ruleCount = builtins.length rulePatterns;
  policySynced =
    ruleCount == 4
    && lib.hasSuffix defaultRuleLine (lib.last rulePatterns)
    && lib.hasInfix actEncryptedRegexLine sopsPolicy;

  listFiles =
    dir: prefix:
    lib.concatLists (
      lib.mapAttrsToList (
        name: type:
        if type == "directory" then
          listFiles (dir + "/${name}") "${prefix}${name}/"
        else if type == "regular" || type == "symlink" then
          [ "${prefix}${name}" ]
        else
          [ ]
      ) (builtins.readDir dir)
    );

  # Deny by default to keep new extensions and extensionless names covered.
  # Exemptions are intentional cleartext conventions: *.example templates,
  # local decryption artifacts, and exact Git metadata names. A .git segment
  # excludes its internal metadata files without exempting .git-* filenames.
  gitMetadataNames = [
    ".git"
    ".gitignore"
    ".gitattributes"
    ".gitmodules"
    ".gitkeep"
  ];
  mustBeEncrypted =
    path:
    let
      base = baseNameOf path;
    in
    !(lib.hasSuffix ".example" path)
    && !(lib.hasPrefix "decrypted_" base)
    && !(lib.hasInfix ".dec." base || (!(lib.hasInfix "/" path) && lib.hasInfix ".dec" base))
    && !(lib.any (part: lib.elem part gitMetadataNames) (lib.splitString "/" path));

  # lib.hasInfix is regex-based and overflows the evaluator stack on
  # megabyte-scale strings (std::regex recursion; the sops-encrypted font
  # blob is ~1 MiB), so scan each needle in bounded chunks with a needle-sized
  # overlap. SOPS 3.13.3 emits lastmodified metadata in every supported
  # encrypted format, using sops_lastmodified for dotenv, so requiring it
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
            "sops-cleartext-check.nix policy mirror drifted from .sops.yaml (rule count, "
            + "deny-by-default pattern, final-rule position, or act.yaml encrypted_regex). A new "
            + "creation rule can narrow encryption via encrypted_regex or a different key group, "
            + "and this check cannot detect that from file content: review the rule against "
            + "modules/security/sops-policy.nix before raising ruleCount."
          )
        else if !secretsPresent then
          pkgs.runCommandLocal "secrets-no-cleartext-skipped" { } ''
            echo "skipped: secrets/ submodule content not present in this checkout" > $out
          ''
        else if cleartext != [ ] then
          throw (
            "secrets/ contains cleartext files matched by .sops.yaml creation_rules: "
            + lib.concatStringsSep ", " cleartext
            + ". Encrypt them, rename them to a *.example template, or rename a "
            + "local decryption artifact to a top-level *.dec* or nested *.dec.* path."
          )
        else
          pkgs.runCommandLocal "secrets-no-cleartext-ok" { } ''
            echo "ok: every non-exempt file under the deny-by-default secrets/ policy carries SOPS MAC and lastmodified markers" > $out
          '';
    };
}

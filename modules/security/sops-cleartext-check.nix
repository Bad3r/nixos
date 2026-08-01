# Regression gate for issue #344: any non-exempt file under secrets/ that the
# .sops.yaml creation_rules mark as encryptable must actually carry the sops
# ENC[AES256_GCM, MAC token.
# The pre-commit ensure-sops hook only sees superproject staged files, so a
# cleartext commit made inside the secrets submodule bypasses it. This check
# scans the checked-out tree the flake actually ships. Its security contract is
# enforced independently of generated-file parity.
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
  sopsPolicy = builtins.readFile ../../.sops.yaml;
  policyLines = lib.splitString "\n" sopsPolicy;

  # Keep security-critical policy invariants independent of the generated-file
  # comparison, so a source change cannot move both sides of the parity check.
  rulePatterns = lib.filter (line: lib.hasPrefix "  - path_regex: " line) policyLines;
  nestedLines = lib.filter (
    line: lib.hasPrefix "    " line && !(lib.hasPrefix "          - " line)
  ) policyLines;
  recipientLines = lib.filter (line: lib.hasPrefix "          - " line) policyLines;
  hostKeyLine = "  - &host_pub_key age1llvnvaarx3l5kn3t4mgggt9khkrv38v4lxsvdleg2rxxslqf0qxsnq4laf\n";
  expectedNestedLines = [
    "    encrypted_regex: \"^(github_token)$\""
    "    key_groups:"
    "      - age:"
    "    key_groups:"
    "      - age:"
    "    key_groups:"
    "      - age:"
    "    key_groups:"
    "      - age:"
  ];
  denyByDefaultSuffix =
    "  - path_regex: secrets/.*\n"
    + "    key_groups:\n"
    + "      - age:\n"
    + "          - *host_pub_key\n";
  actRuleBlock =
    "  - path_regex: secrets/act\\.yaml\n"
    + "    encrypted_regex: \"^(github_token)$\"\n"
    + "    key_groups:\n"
    + "      - age:\n"
    + "          - *host_pub_key\n\n";
  policyFixtures = [
    {
      name = "creation-rule-count";
      want = builtins.length rulePatterns == 4;
    }
    {
      name = "creation-rule-directives";
      want = nestedLines == expectedNestedLines;
    }
    {
      name = "host-recipient-set";
      want = recipientLines == lib.genList (_: "          - *host_pub_key") 4;
    }
    {
      name = "host-key-anchor";
      want = lib.hasInfix hostKeyLine sopsPolicy;
    }
    {
      name = "act-yaml-field-policy";
      want = lib.hasInfix actRuleBlock sopsPolicy;
    }
    {
      name = "deny-by-default-last";
      want = lib.hasSuffix denyByDefaultSuffix sopsPolicy;
    }
  ];
  policyDrift = map (fixture: fixture.name) (lib.filter (fixture: !fixture.want) policyFixtures);

  exemptionFixtures = {
    "notes.md" = true;
    "runbook" = true;
    "sub/NOTES" = true;
    ".git-credentials" = true;
    "sub/prod.dec" = true;
    "url_catalog.dec" = true;
    "config.yaml.example" = false;
    "decrypted_url_catalog.yaml" = false;
    "sub/decrypted_x.yaml" = false;
    "sub/x.dec.yaml" = false;
    "x.dec.yaml" = false;
    ".gitignore" = false;
    ".gitkeep" = false;
    "sub/.gitignore" = false;
    "sub/.gitattributes" = false;
    "sub/.gitmodules" = false;
    "sub/.gitkeep" = false;
    ".git/config" = false;
    ".gitignore/prod-token.yaml" = true;
    ".gitattributes/prod-token.yaml" = true;
    ".gitmodules/prod-token.yaml" = true;
    ".gitkeep/prod-token.yaml" = true;
  };
  exemptionDrift = lib.filter (path: mustBeEncrypted path != exemptionFixtures.${path}) (
    lib.attrNames exemptionFixtures
  );

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

  listSymlinks =
    dir: prefix:
    lib.concatLists (
      lib.mapAttrsToList (
        name: type:
        if type == "directory" then
          listSymlinks (dir + "/${name}") "${prefix}${name}/"
        else if type == "symlink" then
          [ "${prefix}${name}" ]
        else
          [ ]
      ) (builtins.readDir dir)
    );

  # Deny by default to keep new extensions and extensionless names covered.
  # Exemptions are intentional cleartext conventions: *.example templates,
  # local decryption artifacts, exact Git metadata basenames, and .git path
  # segments. A .git segment excludes its internal metadata files without
  # exempting .git-* filenames.
  gitMetadataNames = [
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
    && !(lib.hasInfix ".dec." base)
    && !(lib.elem base gitMetadataNames)
    && !(lib.elem ".git" (lib.splitString "/" path));

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

  # Anchor on SOPS MAC footer fields, not a bare cipher token. Prose can mention
  # ENC[AES256_GCM, and lastmodified without containing encrypted payload data.
  macNeedles = [
    "mac: ENC[AES256_GCM," # YAML
    "\"mac\": \"ENC[AES256_GCM," # JSON with a space
    "\"mac\":\"ENC[AES256_GCM," # compact JSON
    "sops_mac=ENC[AES256_GCM," # dotenv
  ];
  hasSopsMarkers =
    s: lib.any (needle: hasChunkedInfix needle s) macNeedles && hasChunkedInfix "lastmodified" s;

  # Pin the detector in the secretless path so chunk boundaries and both
  # required markers remain covered without relying on submodule payloads.
  markerFixtures = [
    {
      name = "yaml-footer";
      content = "mac: ENC[AES256_GCM,data:x]\nlastmodified: 2026-01-01T00:00:00Z\n";
      want = true;
    }
    {
      name = "json-footer";
      content = "{\"mac\": \"ENC[AES256_GCM,data:x]\", \"lastmodified\": \"2026-01-01T00:00:00Z\"}\n";
      want = true;
    }
    {
      name = "dotenv-footer";
      content = "sops_mac=ENC[AES256_GCM,data:x]\nsops_lastmodified=2026-01-01T00:00:00Z\n";
      want = true;
    }
    {
      name = "quoted-token-only";
      content = "docs quoting ENC[AES256_GCM,data:...] with no sops footer\n";
      want = false;
    }
    {
      name = "prose-with-both-needles";
      content = "requires the ENC[AES256_GCM, marker and sops lastmodified metadata\n";
      want = false;
    }
    {
      name = "cipher-boundary";
      content = lib.concatStrings (lib.genList (_: "x") 8185) + "mac: ENC[AES256_GCM,lastmodified";
      want = true;
    }
    {
      name = "metadata-boundary";
      content = "mac: ENC[AES256_GCM," + lib.concatStrings (lib.genList (_: "x") 8183) + "lastmodified";
      want = true;
    }
  ];
  markerDrift = map (fixture: fixture.name) (
    lib.filter (fixture: hasSopsMarkers fixture.content != fixture.want) markerFixtures
  );

  isCleartext =
    path:
    let
      content = builtins.readFile (secretsDir + "/${path}");
    in
    !(hasSopsMarkers content);

  secretsFiles = if secretsPresent then listFiles secretsDir "" else [ ];
  symlinkFiles = if secretsPresent then listSymlinks secretsDir "" else [ ];
  unsupportedSymlinks = symlinkFiles;
  cleartext = lib.filter isCleartext (lib.filter mustBeEncrypted secretsFiles);
  encryptedTemplates = lib.filter (
    path: lib.hasSuffix ".example" path && !(isCleartext path)
  ) secretsFiles;
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.secrets-no-cleartext =
        # throw, not a failing derivation: CI evaluates check drvPaths with
        # --no-build, so only an eval-time failure gates it (same rationale
        # as modules/meta/ci-lix-parity.nix).
        if policyDrift != [ ] then
          throw (
            "sops-cleartext-check.nix policy security contract drifted: "
            + lib.concatStringsSep ", " policyDrift
            + ". Review modules/security/sops-policy.nix before accepting the change."
          )
        else if exemptionDrift != [ ] then
          throw (
            "sops-cleartext-check.nix mustBeEncrypted classified these paths against "
            + "the documented exemption boundary: "
            + lib.concatStringsSep ", " exemptionDrift
          )
        else if markerDrift != [ ] then
          throw (
            "sops-cleartext-check.nix hasSopsMarkers misclassified these fixtures: "
            + lib.concatStringsSep ", " markerDrift
          )
        else if unsupportedSymlinks != [ ] then
          throw (
            "secrets/ contains symlinks that cannot be scanned: "
            + lib.concatStringsSep ", " unsupportedSymlinks
            + ". Replace them with regular files."
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
            + "local decryption artifact to a decrypted_* or *.dec.* path."
          )
        else if encryptedTemplates != [ ] then
          throw (
            "secrets/ contains *.example templates that carry SOPS markers: "
            + lib.concatStringsSep ", " encryptedTemplates
            + ". The deny-by-default rule matches *.example, so `sops -e -i` on a "
            + "template succeeds; restore the cleartext template from git."
          )
        else
          pkgs.runCommandLocal "secrets-no-cleartext-ok" { } ''
            echo "ok: every non-exempt file under the deny-by-default secrets/ policy carries SOPS MAC and lastmodified markers" > $out
          '';
    };
}

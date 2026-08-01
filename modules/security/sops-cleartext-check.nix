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

  # Compare the committed artifact with the files-module source in perSystem
  # below. Reading config.flake.lib here recurses the flake-parts fixpoint.
  sopsPolicy = builtins.readFile ../../.sops.yaml;
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
        else if type == "regular" || type == "symlink" then
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

  hasSopsMarkers = s: (hasChunkedInfix "ENC[AES256_GCM," s) && (hasChunkedInfix "lastmodified" s);

  # Pin the detector in the secretless path so chunk boundaries and both
  # required markers remain covered without relying on submodule payloads.
  markerFixtures = [
    {
      name = "yaml-footer";
      content = "a: ENC[AES256_GCM,data:x]\nsops:\n  lastmodified: 2026-01-01T00:00:00Z\n";
      want = true;
    }
    {
      name = "dotenv-footer";
      content = "A=ENC[AES256_GCM,data:x]\nsops_lastmodified=2026-01-01T00:00:00Z\n";
      want = true;
    }
    {
      name = "quoted-token-only";
      content = "docs quoting ENC[AES256_GCM,data:...] with no sops footer\n";
      want = false;
    }
    {
      name = "cipher-boundary";
      content = lib.concatStrings (lib.genList (_: "x") 8185) + "ENC[AES256_GCM,lastmodified";
      want = true;
    }
    {
      name = "metadata-boundary";
      content = "ENC[AES256_GCM," + lib.concatStrings (lib.genList (_: "x") 8183) + "lastmodified";
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
  cleartext = lib.filter isCleartext (lib.filter mustBeEncrypted secretsFiles);
  encryptedTemplates = lib.filter (
    path: lib.hasSuffix ".example" path && !(isCleartext path)
  ) secretsFiles;
in
{
  perSystem =
    { config, pkgs, ... }:
    let
      policySynced = config.files.file.".sops.yaml".text == sopsPolicy;
    in
    {
      checks.secrets-no-cleartext =
        # throw, not a failing derivation: CI evaluates check drvPaths with
        # --no-build, so only an eval-time failure gates it (same rationale
        # as modules/meta/ci-lix-parity.nix).
        if !policySynced then
          throw (
            "sops-cleartext-check.nix committed .sops.yaml differs from "
            + "modules/security/sops-policy.nix files-module source. Run write-files and review "
            + "the policy change before accepting it. A new creation rule can narrow encryption "
            + "via encrypted_regex or a different key group, so do not regenerate blindly."
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

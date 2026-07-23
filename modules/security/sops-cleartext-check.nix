# Regression gate for issue #344: any file under secrets/ that the .sops.yaml
# creation_rules mark as encryptable must actually carry the sops
# ENC[AES256_GCM, MAC token.
# The pre-commit ensure-sops hook only sees superproject staged files, so a
# cleartext commit made inside the secrets submodule bypasses it; this check
# scans the checked-out tree the flake actually ships.
{ lib, ... }:
let
  secretsDir = ../../secrets;
  # Absent on checkouts without the initialized submodule (see issue #333);
  # scanning is only meaningful when the content is present.
  secretsPresent = builtins.pathExists (secretsDir + "/.gitignore");

  # Literal mirror of sensitiveExtensions in modules/security/sops-policy.nix.
  # Reading it through config.flake.lib recurses the flake-parts fixpoint, so
  # the sync is enforced below against the generated .sops.yaml instead.
  extAlternation = "yaml|yml|json|env|ini|asc|md|txt";
  catchAllLine = "- path_regex: secrets/.+\\.(${extAlternation})$";
  policySynced = lib.hasInfix catchAllLine (builtins.readFile ../../.sops.yaml);

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

  # Mirrors the creation_rules surface: the extension catch-all plus the
  # fonts/ any-extension rule. Exemptions are the intentional cleartext
  # conventions: *.example templates and the gitignored local-decryption
  # prefixes (decrypted_*, *.dec.*), which reach evaluation only through
  # `path:` flake refs that copy untracked files.
  mustBeEncrypted =
    path:
    let
      base = baseNameOf path;
    in
    !(lib.hasSuffix ".example" path)
    && !(lib.hasPrefix "decrypted_" base)
    && !(lib.hasInfix ".dec." base)
    && (lib.hasPrefix "fonts/" path || builtins.match ".+\\.(${extAlternation})" path != null);

  # lib.hasInfix is regex-based and overflows the evaluator stack on
  # megabyte-scale strings (std::regex recursion; the sops-encrypted font
  # blob is ~1 MiB), so scan in bounded chunks with a marker-length overlap.
  # Match the full `ENC[AES256_GCM,` MAC token, not a bare `ENC[`: cleartext
  # containing `ENC[` (a Markdown fenced block, the #344 content type) would
  # otherwise pass. Fails closed: a cipher change flags real ciphertext rather
  # than admitting cleartext.
  hasEncMarker =
    s:
    let
      len = builtins.stringLength s;
      chunkSize = 8192;
      overlap = builtins.stringLength "ENC[AES256_GCM,";
      go =
        i:
        i < len
        && (
          builtins.match ".*ENC\\[AES256_GCM,.*" (builtins.substring i (chunkSize + overlap) s) != null
          || go (i + chunkSize)
        );
    in
    go 0;

  isCleartext = path: !(hasEncMarker (builtins.readFile (secretsDir + "/${path}")));

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
        if !secretsPresent then
          pkgs.runCommandLocal "secrets-no-cleartext-skipped" { } ''
            echo "skipped: secrets/ submodule content not present in this checkout" > $out
          ''
        else if !policySynced then
          throw (
            "sops-cleartext-check.nix extension list drifted from the .sops.yaml catch-all rule; "
            + "update extAlternation to match modules/security/sops-policy.nix"
          )
        else if cleartext != [ ] then
          throw (
            "secrets/ contains cleartext files matched by .sops.yaml creation_rules: "
            + lib.concatStringsSep ", " cleartext
            + ". Encrypt them with sops or rename them to a *.example template."
          )
        else
          pkgs.runCommandLocal "secrets-no-cleartext-ok" { } ''
            echo "ok: every creation_rules-matched file under secrets/ carries ENC[ markers" > $out
          '';
    };
}

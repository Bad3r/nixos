# A gitleaks allowlist entry under `paths` skips the whole file before its
# contents are scanned, so path-scoping anything in secrets/ hides every real
# credential in that file, not just the false positive the entry was added for.
# Measured with gitleaks 8.30.1: allowlisting secrets/private-ops/.* dropped the
# scan to 0 bytes and a planted Stripe live key and Slack bot token in that same
# file both went undetected. The Cloudflare KV allowlist in
# modules/development/gitleaks.nix is line-scoped for that reason, and this
# check fails if any allowlist ever path-scopes the secrets tree instead.
# throw, not a failing derivation: CI runs `nix flake check --no-build`,
# which evaluates check attrs but never builds them, so only an eval-time
# failure gates CI.
{ lib, ... }:
let
  configFile = ../../.gitleaks.toml;

  # Drop the preamble before the first table so every element is one allowlist.
  blocks = lib.drop 1 (lib.splitString "[[allowlists]]" (builtins.readFile configFile));

  # The literal text between `paths = [` and its closing bracket, or null when
  # the allowlist has no paths key at all.
  pathsBodyOf =
    block:
    let
      afterKey = lib.splitString "paths = [" block;
    in
    if lib.length afterKey < 2 then null else lib.head (lib.splitString "]" (lib.elemAt afterKey 1));

  pathScopedSecrets = lib.filter (body: body != null && lib.hasInfix "secrets" body) (
    map pathsBodyOf blocks
  );

  # The Cloudflare KV allowlist stays a no-op unless it is line-scoped: matched
  # against the default target the regex sees the bare hex secret and never the
  # surrounding "keys KV:" text.
  kvBlocks = lib.filter (block: lib.hasInfix "keys KV" block) blocks;
  kvUnscoped = lib.filter (block: !lib.hasInfix ''regexTarget = "line"'' block) kvBlocks;
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.gitleaks-allowlist-scope =
        if pathScopedSecrets != [ ] then
          throw (
            "gitleaks-allowlist-scope: an allowlist in .gitleaks.toml path-scopes the "
            + "secrets tree, which skips those files entirely and hides real leaks in "
            + "them; scope the allowlist with regexTarget = \"line\" instead "
            + "(modules/development/gitleaks.nix)"
          )
        else if kvBlocks == [ ] then
          throw (
            "gitleaks-allowlist-scope: the Cloudflare KV namespace allowlist is gone "
            + "from .gitleaks.toml; drop this check with it "
            + "(modules/development/gitleaks.nix)"
          )
        else if kvUnscoped != [ ] then
          throw (
            "gitleaks-allowlist-scope: the Cloudflare KV namespace allowlist lost "
            + "regexTarget = \"line\", so its regex is matched against the bare secret "
            + "and never fires (modules/development/gitleaks.nix)"
          )
        else
          pkgs.runCommandLocal "gitleaks-allowlist-scope-ok" { } ''
            echo "ok: no gitleaks allowlist path-scopes the secrets tree" > $out
          '';
    };
}

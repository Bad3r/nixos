_: {
  # Generate and manage the project .gitleaks.toml via the files module
  # Pattern mirrors modules/development/gitignore.nix
  perSystem =
    _:
    let
      # Shared by both configs: content-scoped only, so nothing here depends on
      # which repository's path space the scan is rooted in.
      contentAllowlists = ''
        [[allowlists]]
        description = "DNSCrypt resolvers-list public minisign verification key"
        regexes = [
          "RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3",
        ]

        [[allowlists]]
        description = "Cloudflare KV namespace IDs recorded in operational notes"
        # A namespace id is a resource identifier, not a credential; reaching the
        # namespace still needs an account id plus an API token. generic-api-key
        # fires only because the bullet names what the namespace stores ("keys").
        # Line-scoped, never path-scoped: a `paths` entry makes gitleaks skip the
        # whole file before scanning it, which would hide real leaks in the same
        # note. Anchors are omitted because regexTarget "line" does not match
        # against a bare trimmed line.
        regexTarget = "line"
        # Rule-scoped, because a global allowlist is evaluated against every
        # finding of every rule and a line-target match drops it outright: without
        # this, any line carrying the text below also hides a real credential
        # placed on the same line. Measured on 8.30.1, a Stripe live key alone is
        # reported and the same key followed by "# production keys KV: <32 hex>"
        # is not. That is broader than anything gitleaks-allowlist-scope bans and
        # is the one vector it cannot reach, being triggered by file content
        # rather than by config.
        targetRules = [
          "generic-api-key",
        ]
        regexes = [
          "(production|preview) keys KV: [0-9a-f]{32}",
        ]
      '';
    in
    {
      files.file.".gitleaks.toml".text = ''
        # Inherit the upstream default ruleset and extend with repo-local
        # allowlists for documentation-only directories that contain
        # example secrets, and for well-known public keys used for
        # upstream signature verification.
        # Superproject pass only. The submodule pass reads
        # .gitleaks-secrets.toml, because path patterns are matched against a
        # File rooted at whichever tree is being scanned.
        [extend]
        useDefault = true

        [[allowlists]]
        description = "Documentation examples with placeholder secrets"
        paths = [
          # Anchored: gitleaks matches paths unanchored against a repo-relative
          # File, so "nixos-manual/.*" also skips secrets/private-ops/nixos-manual
          # and every other directory of that name, making the one reviewed
          # path-scope reachable by creating a directory instead of by editing
          # config. Keep the old root-level path because gitleaks scans historical
          # commits.
          "^nixos-manual/",
          "^docs/nixos-manual/",
        ]

        ${contentAllowlists}
      '';

      # The submodule pass's config. Anchoring the two documentation paths pins
      # them to the top of the tree being scanned, and for `gitleaks git secrets`
      # that tree is the submodule: File comes back as "nixos-manual/leak.txt",
      # not "secrets/nixos-manual/leak.txt", so a shared config would skip a
      # top-level nixos-manual/ inside the private repository before scanning it.
      # That is reachable by creating a directory there, with no config edit and
      # nothing visible from this repository, which is the reachability anchoring
      # the paths was meant to remove. No paths key at all here, and
      # gitleaks-allowlist-scope pins that with an empty reviewed set for this
      # origin.
      files.file.".gitleaks-secrets.toml".text = ''
        # Read only by the submodule pass in modules/meta/hooks/gitleaks.nix.
        # Content-scoped allowlists only: a paths entry here would be matched
        # against the private repository's own path space, which no reviewer of
        # this repository can see.
        [extend]
        useDefault = true

        ${contentAllowlists}
      '';
    };
}

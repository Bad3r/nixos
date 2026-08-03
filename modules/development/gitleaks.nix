_: {
  # Generate and manage the project .gitleaks.toml via the files module
  # Pattern mirrors modules/development/gitignore.nix
  perSystem =
    _:
    let
      # Shared by both configs: content-scoped only, so nothing here depends on
      # which repository's path space the scan is rooted in.
      sharedContentAllowlists = ''
        [[allowlists]]
        description = "DNSCrypt resolvers-list public minisign verification key"
        regexes = [
          "RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3",
        ]
      '';

      secretOnlyAllowlists = ''
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
      files.file = {
        ".gitleaks.toml".text = ''
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

          ${sharedContentAllowlists}
        '';

        # The submodule pass's config is the only config that carries the KV
        # namespace allowlist, because the operational note lives in that private
        # repository and the superproject must not gain a content-based suppression
        # channel for public files.
        # No paths key at all here: a paths entry would be matched against the
        # private repository's own path space, which no reviewer of this repository
        # can see. gitleaks-allowlist-scope pins that with an empty reviewed set for
        # this origin.
        ".gitleaks-secrets.toml".text = ''
          # Read only by the submodule pass in modules/meta/hooks/gitleaks.nix.
          # Content-scoped allowlists only: a paths entry here would be matched
          # against the private repository's own path space, which no reviewer of
          # this repository can see.
          [extend]
          useDefault = true

          ${sharedContentAllowlists}
          ${secretOnlyAllowlists}
        '';

        # Other gitlinks use a content-only config without the private operational
        # note allowlist. The hook selects .gitleaks-secrets.toml only for the
        # pinned private gitlinks and this file for every other gitlink.
        ".gitleaks-gitlink.toml".text = ''
          # Read by gitlink passes that do not own the private operational note.
          # Content-scoped allowlists only: no gitlink path is reviewed here.
          [extend]
          useDefault = true

          ${sharedContentAllowlists}
        '';
      };
    };
}

_: {
  # Generate and manage the project .gitignore via the files module
  # Pattern mirrors modules/development/act.nix and modules/readme.nix
  perSystem =
    { pkgs, ... }:
    {
      files.files = [
        {
          path_ = ".gitignore";
          drv = pkgs.writeText ".gitignore" ''
            ########################################
            # NixOS / Flakes outputs
            ########################################
            # Common Nix build symlinks
            /result
            /result-*
            /result.*
            *.log

            ########################################
            # Dev shells & tooling
            ########################################
            # lefthook local overrides (user-specific, not committed)
            /lefthook-local.yml

            # claude code testing
            .mcp.json
            .specify/

            # direnv state
            .direnv/
            .envrc.local

            # Tool/LSP caches (top-level and nested)
            .clj-kondo/
            .lsp/
            .claude/
            **/.clj-kondo/**
            **/.lsp/**
            .kiro/
            tmp/
            .tmp/
            .code/
            **/__pycache__
            .vscode/
            .log/
            log/
            ########################################
            # Editors, OS cruft, and temp files
            ########################################
            .idea/
            .DS_Store
            Thumbs.db
            *.swp
            *.swo
            *~
            *.tgz
            ########################################
            # Language/vendor caches (safe defaults)
            ########################################
            node_modules/
            .cache/

            ########################################
            # Secrets safety (defense-in-depth)
            # Do not commit private keys or local env files
            ########################################
            *.agekey
            *.key
            *.pem
            *.p12
            *.pfx
            .env
            .env.*
            # Common SSH/private key patterns (allow public keys)
            id_*
            !id_*.pub

            # If decrypting SOPS files locally, ignore any decrypted outputs in secrets/
            secrets/*.dec*
          '';
        }
      ];
    };
}

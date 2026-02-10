_: {
  perSystem =
    { pkgs, ... }:
    {
      packages.hook-vulnix = pkgs.writeShellApplication {
        name = "hook-vulnix";
        runtimeInputs = [ pkgs.vulnix ];
        text = # bash
          ''
            set -euo pipefail

            WHITELIST="vulnix-whitelist.toml"
            if [ ! -f "$WHITELIST" ]; then
              echo "vulnix: whitelist not found: $WHITELIST" >&2
              exit 1
            fi

            if ! vulnix -S -w "$WHITELIST"; then
              if [ "''${VULNIX_ENFORCE:-0}" != "1" ]; then
                echo ""
                echo "⚠ vulnix: unwhitelisted CVEs found (warning-only mode)"
                echo "  Set VULNIX_ENFORCE=1 to make this hook blocking."
                exit 0
              fi
              echo ""
              echo "✗ vulnix: unwhitelisted CVEs found."
              echo "  Review findings above and update vulnix-whitelist.toml only for accepted risk."
              exit 1
            fi
          '';
      };
    };
}

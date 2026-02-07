_: {
  perSystem =
    { pkgs, ... }:
    {
      packages.lefthook-vulnix = pkgs.writeShellApplication {
        name = "lefthook-vulnix";
        runtimeInputs = [ pkgs.vulnix ];
        text = # bash
          ''
            WHITELIST="vulnix-whitelist.toml"
            if [ ! -f "$WHITELIST" ]; then
              echo "vulnix: whitelist not found: $WHITELIST" >&2
              exit 1
            fi
            if ! vulnix -S -w "$WHITELIST"; then
              echo ""
              echo "⚠ vulnix: unwhitelisted CVEs found (warning only, not blocking commit)"
              echo "  Review findings above and update vulnix-whitelist.toml for false positives."
            fi
          '';
      };
    };
}

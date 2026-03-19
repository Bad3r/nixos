_: {
  perSystem =
    { pkgs, ... }:
    {
      packages.hook-mcp-docs-sync = pkgs.writeShellApplication {
        name = "hook-mcp-docs-sync";
        runtimeInputs = [
          pkgs.git
          pkgs.nix
          pkgs.coreutils
          pkgs.diffutils
          pkgs.gnused
        ];
        text = # bash
          ''
            set -euo pipefail

            root=$(git rev-parse --show-toplevel)
            cd "$root"

            doc_file="docs/reference/mcp-tools.md"
            tmp_expected=$(mktemp)
            tmp_diff=$(mktemp)
            trap 'rm -f "$tmp_expected" "$tmp_diff"' EXIT

            if ! nix eval --raw .#lib.agents.mcp.docs.referenceMarkdown > "$tmp_expected"; then
              echo "✗ Failed to generate expected MCP docs markdown." >&2
              echo "Run the regeneration command manually and retry." >&2
              exit 1
            fi

            if cmp -s "$tmp_expected" "$doc_file"; then
              exit 0
            fi

            echo "" >&2
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
            echo "❌ Error: docs/reference/mcp-tools.md is out of sync with agents.mcp" >&2
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
            echo "" >&2
            echo "Short diff preview:" >&2
            if diff -u --label "$doc_file(expected)" "$tmp_expected" --label "$doc_file" "$doc_file" > "$tmp_diff"; then
              :
            fi
            head -n 40 "$tmp_diff" | sed 's/^/    /' >&2 || true
            echo "" >&2
            echo "Regenerate with:" >&2
            echo "  tmp=\$(mktemp) && nix eval --raw .#lib.agents.mcp.docs.referenceMarkdown > \"\$tmp\" && mv \"\$tmp\" docs/reference/mcp-tools.md" >&2
            echo "Then stage docs/reference/mcp-tools.md and commit normally." >&2
            exit 1
          '';
      };
    };
}

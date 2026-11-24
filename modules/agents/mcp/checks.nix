{ config, lib, ... }:
let
  agents = config.flake.lib.agents;
  plugins = import ../_plugins.nix;
in
{
  perSystem =
    { pkgs, ... }:
    let
      emptyOsConfig = { };
      fullOsConfig = {
        programs = {
          sbx.extended = {
            enable = true;
            finalPackage = pkgs.emptyDirectory;
            limits.maxTtl = 1;
          };
          chatgpt.extended = {
            enable = true;
            finalPackage = {
              unwrapped = pkgs.emptyDirectory;
              version = "1.2.3";
            };
          };
          camoufox.extended = {
            enable = true;
            finalPackage = pkgs.emptyDirectory // {
              meta.mainProgram = "camoufox";
            };
          };
          geckodriver.extended = {
            enable = true;
            finalPackage = pkgs.emptyDirectory;
          };
        };
      };

      nodeReplOverrides = {
        node_repl = import ../codex/_node-repl.nix {
          configDir = "/home/test/.config/codex";
          profileDirectory = "/etc/profiles/per-user/test";
          inherit
            (
              (agents.mcp.mkServer {
                inherit pkgs;
                osConfig = fullOsConfig;
              } "node_repl")
            )
            command
            ;
          inherit (fullOsConfig.programs.chatgpt.extended.finalPackage) version;
        };
      };

      codexServers = agents.mcp.clients.codex.servers {
        inherit pkgs;
        osConfig = fullOsConfig;
        serverOverrides = nodeReplOverrides;
      };
      antigravityServers = agents.mcp.clients.antigravity.servers {
        inherit pkgs;
        osConfig = emptyOsConfig;
      };
      claudeServers = agents.mcp.clients.claude.servers {
        inherit pkgs;
        osConfig = emptyOsConfig;
      };

      codexManifest = agents.mcp.clients.codex.manifest {
        inherit pkgs;
        osConfig = fullOsConfig;
        serverOverrides = nodeReplOverrides;
      };
      antigravityManifest = agents.mcp.clients.antigravity.manifest {
        inherit pkgs;
        osConfig = emptyOsConfig;
      };
      claudeManifest = agents.mcp.clients.claude.manifest {
        inherit pkgs;
        osConfig = emptyOsConfig;
      };

      allClientServers = [
        codexServers
        antigravityServers
        claudeServers
      ];
      allManifests = [
        codexManifest
        antigravityManifest
        claudeManifest
      ];
      hasOnlyCodemode = servers: lib.attrNames servers == [ "codemode" ];
      manifestJson = builtins.toJSON allManifests;
      gdkMeta = agents.mcp.servers.google-developer-knowledge;
      cfApiMeta = agents.mcp.servers.cloudflare-api;
      expectedPackSkills = [
        "chrome-extensions"
        "cloudflare"
        "modern-web-guidance"
        "wrangler"
      ];
      packDirsByClient = lib.genAttrs [
        "antigravity"
        "claude"
        "codex"
      ] (client: agents.skills.packDirsFor client emptyOsConfig);
    in
    {
      checks."agents/mcp/codemode" =
        assert lib.assertMsg (lib.all hasOnlyCodemode allClientServers)
          "every managed client must expose only the single `codemode` MCP server";
        assert lib.assertMsg (
          !(agents.mcp.servers ? cfdocs)
        ) "retired cfdocs MCP server must be removed from servers.nix";
        assert lib.assertMsg (
          codexServers.codemode.tool_timeout_sec == 3600
        ) "codex codemode tool_timeout_sec must reflect enabled sbx maxTtl";
        assert lib.assertMsg (lib.elem "BROWSER_USE_ACCESS_PIPE_PATH" (
          codexServers.codemode.env_vars or [ ]
        )) "codex codemode entry must forward node_repl env_vars when chatgpt is enabled";
        assert lib.assertMsg (
          codexManifest.servers.node_repl.env.BROWSER_USE_CODEX_APP_VERSION == "1.2.3"
        ) "codex manifest must carry _node-repl.nix environment for node_repl";
        assert lib.assertMsg (lib.all
          (
            m:
            m.servers ? cloudflare-api
            && m.servers.cloudflare-api.enabled == true
            && m.servers.cloudflare-api.url == cfApiMeta.url
            && m.servers.cloudflare-api.secretHeader == cfApiMeta.secretHeader
            && m.servers.cloudflare-api.secretHeader.prefix == "Bearer "
          )
          allManifests
        ) "every client manifest must include enabled cloudflare-api with Bearer secretHeader";
        assert lib.assertMsg (lib.all (
          m: m.servers ? context7 && m.servers.context7.enabled == true
        ) allManifests) "every client manifest (including claude) must include enabled context7";
        assert lib.assertMsg (lib.all
          (
            m:
            m.servers ? google-developer-knowledge
            && m.servers.google-developer-knowledge.enabled == false
            && m.servers.google-developer-knowledge.url == gdkMeta.url
            && m.servers.google-developer-knowledge.secretHeader == gdkMeta.secretHeader
          )
          allManifests
        ) "every client manifest must include disabled google-developer-knowledge with secretHeader";
        assert lib.assertMsg (
          antigravityManifest.servers.deepwiki.enabled == true
          && claudeManifest.servers.deepwiki.enabled == true
          && codexManifest.servers.deepwiki.enabled == true
        ) "default-enabled servers must remain enabled in every client manifest";
        assert lib.assertMsg (
          !(lib.hasInfix "AIza" manifestJson)
        ) "compiled manifests must never embed secret values";
        assert lib.assertMsg
          (
            plugins."cloudflare@claude-plugins-official".claude-code == false
            && plugins."cloudflare@claude-plugins-official".codex == false
            && plugins."cloudflare@antigravity-plugins-partners"."antigravity-cli" == false
            && plugins."modern-web-guidance-plugin@antigravity-plugins-official"."antigravity-cli" == false
          )
          "replaced marketplace Cloudflare and Modern Web Guidance plugins must be disabled in _plugins.nix";
        assert lib.assertMsg (
          plugins."android-cli-plugin@antigravity-plugins-official"."antigravity-cli" == true
          && plugins."chrome-devtools-plugin@antigravity-plugins-official"."antigravity-cli" == true
        ) "installed skills-only Antigravity plugins must be enabled in _plugins.nix";
        assert lib.assertMsg (
          !(plugins ? "gdrive@antigravity-plugins-official")
        ) "gdrive@antigravity-plugins-official must be removed from _plugins.nix";
        assert lib.assertMsg (
          plugins."google-developer-knowledge@antigravity-plugins-official"."antigravity-cli" == false
        ) "google-developer-knowledge@antigravity-plugins-official must be disabled in _plugins.nix";
        assert lib.assertMsg (
          !(plugins ? "google-developer-knowledge@nixos-local")
        ) "legacy google-developer-knowledge@nixos-local plugin must be removed from _plugins.nix";
        assert lib.assertMsg (lib.all
          (client: lib.all (skill: packDirsByClient.${client} ? ${skill}) expectedPackSkills)
          (lib.attrNames packDirsByClient)
        ) "cloudflare-skills and modern-web-guidance skill packs must compile for all three clients";
        pkgs.runCommandLocal "agents-mcp-codemode-check"
          {
            passthru.runtimeCheck = true;
            nativeBuildInputs = [ pkgs.jq ];
          }
          ''
            set -euo pipefail
            for manifest in \
              ${pkgs.writeText "codex-manifest.json" (builtins.toJSON codexManifest)} \
              ${pkgs.writeText "antigravity-manifest.json" (builtins.toJSON antigravityManifest)} \
              ${pkgs.writeText "claude-manifest.json" (builtins.toJSON claudeManifest)}; do
              jq -e '.servers["cloudflare-api"].enabled == true' "$manifest" >/dev/null
              jq -e '.servers["cloudflare-api"].secretHeader.name == "Authorization"' "$manifest" >/dev/null
              jq -e '.servers["cloudflare-api"].secretHeader.prefix == "Bearer "' "$manifest" >/dev/null
              jq -e '.servers["context7"].enabled == true' "$manifest" >/dev/null
              jq -e '.servers["google-developer-knowledge"].enabled == false' "$manifest" >/dev/null
              jq -e '.servers["google-developer-knowledge"].secretHeader.name == "X-Goog-Api-Key"' "$manifest" >/dev/null
            done
            touch "$out"
          '';
    };
}

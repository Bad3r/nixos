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
      };
      antigravityManifest = agents.mcp.clients.antigravity.manifest {
        inherit pkgs;
        osConfig = emptyOsConfig;
      };
      claudeManifest = agents.mcp.clients.claude.manifest {
        inherit pkgs;
        osConfig = emptyOsConfig;
      };

      allManifests = [
        codexManifest
        antigravityManifest
        claudeManifest
      ];
      codemodePkg = pkgs.callPackage ../../../packages/mcp-codemode { };
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
      ] agents.skills.packDirsFor;
    in
    {
      checks."agents/mcp/codemode" =
        assert lib.assertMsg (
          lib.attrNames codexServers == [
            "codemode"
            "node_repl"
            "sbx"
          ]
          && lib.attrNames antigravityServers == [ "codemode" ]
          && lib.attrNames claudeServers == [ "codemode" ]
        ) "clients must expose `codemode` alongside direct-only local servers (`node_repl`, `sbx`)";
        assert lib.assertMsg
          (lib.all (name: !(agents.mcp.servers ? ${name})) [
            "cfdocs"
            "cfbrowser"
            "cfbuilds"
            "cfobservability"
            "cfbindings"
            "cfradar"
            "cfcontainers"
            "cfgraphql"
          ])
          "retired separate Cloudflare MCP servers must be removed from servers.nix in favor of cloudflare-api";
        assert lib.assertMsg (
          codexServers.sbx.tool_timeout_sec == 3600
          && codexServers.sbx.default_tools_approval_mode == "approve"
          && agents.mcp.clients.antigravity.autoApproved fullOsConfig == [ "sbx" ]
          && agents.mcp.clients.claude.autoApproved fullOsConfig == [ "sbx" ]
        ) "direct sbx must preserve TTL timeout and auto-approval without auto-approving codemode";
        assert lib.assertMsg (
          codexServers.node_repl.env.BROWSER_USE_CODEX_APP_VERSION == "1.2.3"
          && lib.elem "BROWSER_USE_ACCESS_PIPE_PATH" codexServers.node_repl.env_vars
          && !(lib.elem "BROWSER_USE_ACCESS_PIPE_PATH" codexServers.codemode.env_vars)
          && !(codexManifest.servers ? node_repl)
          && !(codexManifest.servers ? sbx)
        ) "direct servers must stay out of codemode manifests and keep node_repl IPC env isolated";
        assert lib.assertMsg
          (
            codexServers.codemode.tool_timeout_sec == 240
            && antigravityServers.codemode.timeoutSeconds == 240
            && claudeServers.codemode.timeout == 240000
            && !(claudeServers.codemode ? tool_timeout_sec)
            && !(claudeServers.codemode ? startup_timeout_sec)
            &&
              codexServers.codemode.args == [
                "serve"
                "--manifest"
                (builtins.elemAt codexServers.codemode.args 2)
                "--timeout"
                "225"
              ]
            &&
              antigravityServers.codemode.args == [
                "serve"
                "--manifest"
                (builtins.elemAt antigravityServers.codemode.args 2)
                "--timeout"
                "225"
              ]
            &&
              claudeServers.codemode.args == [
                "serve"
                "--manifest"
                (builtins.elemAt claudeServers.codemode.args 2)
                "--timeout"
                "225"
              ]
          )
          "client codemode entries must stay bounded at 240s (with 225s gateway headroom) and client-native timeout keys";
        assert lib.assertMsg (
          lib.elem "MCP_CODEMODE_ENABLE" codexServers.codemode.env_vars
          && lib.elem "MCP_CODEMODE_DISABLE" codexServers.codemode.env_vars
          && lib.elem "XDG_STATE_HOME" codexServers.codemode.env_vars
          && lib.elem "XDG_DATA_HOME" codexServers.codemode.env_vars
        ) "codex codemode entry must forward MCP_CODEMODE_* and XDG_* env_vars";
        assert lib.assertMsg
          (lib.all (
            m:
            m.servers ? cloudflare-api
            && m.servers.cloudflare-api.enabled == true
            && m.servers.cloudflare-api.url == cfApiMeta.url
            && m.servers.cloudflare-api.toolTimeoutSec == 180
            && m.servers.cloudflare-api.secretHeader == cfApiMeta.secretHeader
            && m.servers.cloudflare-api.secretHeader.prefix == "Bearer "
          ) allManifests)
          "every client manifest must include enabled cloudflare-api with 180s toolTimeoutSec and its secret header";
        assert lib.assertMsg (lib.all
          (
            m:
            m.servers ? context7
            && m.servers.context7.enabled == true
            && m.servers.context7.toolTimeoutSec == 180
          )
          allManifests
        ) "every client manifest (including claude) must include enabled context7 with 180s toolTimeoutSec";
        assert lib.assertMsg
          (lib.all (
            m:
            m.servers ? google-developer-knowledge
            && m.servers.google-developer-knowledge.enabled == false
            && m.servers.google-developer-knowledge.url == gdkMeta.url
            && m.servers.google-developer-knowledge.toolTimeoutSec == 180
            && m.servers.google-developer-knowledge.secretHeader == gdkMeta.secretHeader
          ) allManifests)
          "every client manifest must include disabled google-developer-knowledge with 180s toolTimeoutSec and its secret header";
        assert lib.assertMsg (
          antigravityManifest.servers.deepwiki.enabled == true
          && antigravityManifest.servers.deepwiki.toolTimeoutSec == 180
          && claudeManifest.servers.deepwiki.enabled == true
          && codexManifest.servers.deepwiki.enabled == true
        ) "default-enabled servers must remain enabled with 180s toolTimeoutSec in every client manifest";
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
          plugins."gdrive@antigravity-plugins-official"."antigravity-cli" == false
        ) "gdrive@antigravity-plugins-official must stay explicitly disabled in _plugins.nix";
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
            nativeBuildInputs = [
              pkgs.jq
              codemodePkg
            ];
          }
          ''
            set -euo pipefail
            export XDG_STATE_HOME="$TMPDIR/state"
            for manifest in \
              ${pkgs.writeText "codex-manifest.json" (builtins.toJSON codexManifest)} \
              ${pkgs.writeText "antigravity-manifest.json" (builtins.toJSON antigravityManifest)} \
              ${pkgs.writeText "claude-manifest.json" (builtins.toJSON claudeManifest)}; do
              jq empty "$manifest"
              mcp-codemode status --manifest "$manifest" --json >/dev/null
            done
            touch "$out"
          '';
    };
}

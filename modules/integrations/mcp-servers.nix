/*
  MCP (Model Context Protocol) Server Configuration

  This module provides flake.lib.mcp with:
    - serverCatalog: Single source of truth for available MCP servers
    - mkServers: Build server configs from a list of names

  Source types:
    - nix: Packages from mcp-servers-nix (fully reproducible)
    - sse: Remote SSE servers bridged via mcp-remote
    - npx: NPM packages fetched at runtime

  Consumers:
    - modules/hm-apps/claude-code.nix
    - modules/hm-apps/codex.nix
*/
{ lib, inputs, ... }:
let
  # ════════════════════════════════════════════════════════════════════════════
  # Type Definitions - Server Catalog Entry Schema
  # ════════════════════════════════════════════════════════════════════════════

  validSources = [
    "nix"
    "sse"
    "npx"
  ];

  # Required fields per source type
  requiredFields = {
    nix = [ "package" ];
    sse = [ "url" ];
    npx = [ "package" ];
  };

  # Optional fields per source type
  optionalFields = {
    nix = [ "secretEnvVar" ];
    sse = [ "timeout" ];
    npx = [
      "timeout"
      "args"
    ];
  };

  # Validate a single catalog entry
  validateEntry =
    name: entry:
    let
      source = entry.source or (throw "MCP server '${name}': missing required field 'source'");
      validSource = lib.elem source validSources;
      required = requiredFields.${source} or [ ];
      optional = optionalFields.${source} or [ ];
      allowedFields = [ "source" ] ++ required ++ optional;
      entryFields = lib.attrNames entry;
      missingFields = lib.filter (f: !(entry ? ${f})) required;
      extraFields = lib.filter (f: !(lib.elem f allowedFields)) entryFields;
    in
    if !validSource then
      throw "MCP server '${name}': invalid source '${source}'. Valid: ${toString validSources}"
    else if missingFields != [ ] then
      throw "MCP server '${name}' (${source}): missing required fields: ${toString missingFields}"
    else if extraFields != [ ] then
      throw "MCP server '${name}' (${source}): unknown fields: ${toString extraFields}. Allowed: ${toString allowedFields}"
    else
      entry;

  # Validate all catalog entries
  validateCatalog = lib.mapAttrs validateEntry;

  # ════════════════════════════════════════════════════════════════════════════
  # Server Catalog - Single Source of Truth
  # ════════════════════════════════════════════════════════════════════════════
  serverCatalog = validateCatalog {
    # ──────────────────────────────────────────────────────────────────────────
    # Nix packages (mcp-servers-nix, fully reproducible)
    # ──────────────────────────────────────────────────────────────────────────
    sequential-thinking = {
      source = "nix";
      package = "mcp-server-sequential-thinking";
    };

    memory = {
      source = "nix";
      package = "mcp-server-memory";
    };

    context7 = {
      source = "nix";
      package = "context7-mcp";
      secretEnvVar = "CONTEXT7_API_KEY";
    };

    # ──────────────────────────────────────────────────────────────────────────
    # SSE servers (remote, bridged via mcp-remote)
    # ──────────────────────────────────────────────────────────────────────────
    cfdocs = {
      source = "sse";
      url = "https://docs.mcp.cloudflare.com/sse";
    };

    cfbrowser = {
      source = "sse";
      url = "https://browser.mcp.cloudflare.com/sse";
    };

    cfbuilds = {
      source = "sse";
      url = "https://builds.mcp.cloudflare.com/sse";
    };

    cfobservability = {
      source = "sse";
      url = "https://observability.mcp.cloudflare.com/sse";
    };

    cfbindings = {
      source = "sse";
      url = "https://bindings.mcp.cloudflare.com/sse";
    };

    cfradar = {
      source = "sse";
      url = "https://radar.mcp.cloudflare.com/sse";
    };

    cfcontainers = {
      source = "sse";
      url = "https://containers.mcp.cloudflare.com/sse";
    };

    cfgraphql = {
      source = "sse";
      url = "https://graphql.mcp.cloudflare.com/sse";
    };

    openaiDeveloperDocs = {
      source = "sse";
      url = "https://developers.openai.com/mcp";
    };

    # ──────────────────────────────────────────────────────────────────────────
    # NPX packages (fetched at runtime)
    # ──────────────────────────────────────────────────────────────────────────
    deepwiki = {
      source = "npx";
      package = "mcp-deepwiki@latest";
    };

    chrome-devtools = {
      source = "npx";
      package = "chrome-devtools-mcp@latest";
      # Privacy + safety defaults; browser executable is resolved by mkServerConfig.
      args = [
        "--isolated"
        "--no-usage-statistics"
      ];
      timeout = 120;
    };

    playwright = {
      source = "npx";
      package = "@playwright/mcp@latest";
      # Keep browser state isolated; browser executable is resolved by mkServerConfig.
      args = [ "--isolated" ];
      timeout = 120;
    };
  };

  # Timeout in seconds (used by Codex via startup_timeout_sec)
  # Also converted to milliseconds for Claude Code (startup_timeout_ms)
  defaultTimeoutSec = 30;

  # Helper to generate both timeout formats for cross-tool compatibility
  # Codex uses startup_timeout_sec, Claude Code uses startup_timeout_ms
  mkTimeouts = sec: {
    startup_timeout_sec = sec; # Codex
    startup_timeout_ms = sec * 1000; # Claude Code
  };

  # ════════════════════════════════════════════════════════════════════════════
  # Builder Functions
  # ════════════════════════════════════════════════════════════════════════════

  # Build config for a single server
  # mkServerConfig :: { pkgs, mcpPkgs } -> String -> AttrSet
  mkServerConfig =
    { pkgs, mcpPkgs }:
    name:
    let
      meta =
        serverCatalog.${name}
          or (throw "Unknown MCP server: ${name}. Valid: ${toString (lib.attrNames serverCatalog)}");

      timeouts = mkTimeouts (meta.timeout or defaultTimeoutSec);

      # Dispatch table for source types
      handlers = {
        nix =
          let
            pkg = mcpPkgs.${meta.package};
            binPath = "${pkg}/bin/${meta.package}";
          in
          if meta ? secretEnvVar then
            let
              wrapper = pkgs.writeShellApplication {
                name = "${name}-wrapper";
                runtimeInputs = [
                  pkgs.coreutils
                  pkg
                ];
                text = /* bash */ ''
                  secret_path="''${XDG_DATA_HOME:-$HOME/.local/share}/context7/api-key"
                  if [ ! -r "$secret_path" ]; then
                    echo "${name}: missing secret at $secret_path" >&2
                    exit 1
                  fi
                  # shellcheck disable=SC2155
                  export ${meta.secretEnvVar}="$(tr -d '\n' < "$secret_path")"
                  exec ${binPath} "$@"
                '';
              };
            in
            {
              command = "${wrapper}/bin/${name}-wrapper";
              args = [ ];
            }
            // timeouts
          else
            {
              command = binPath;
              args = [ ];
            }
            // timeouts;

        sse = {
          command = "${lib.getExe' pkgs.nodejs "npx"}";
          args = [
            "mcp-remote"
            meta.url
          ];
        }
        // timeouts;

        npx =
          if name == "playwright" then
            let
              wrapper = pkgs.writeShellScriptBin "playwright-mcp-wrapper" ''
                set -euo pipefail

                browser_executable=""
                browser_flag=""

                for candidate in google-chrome-stable google-chrome chromium chromium-browser; do
                  if command -v "$candidate" >/dev/null 2>&1; then
                    browser_executable="$(command -v "$candidate")"
                    if [ "$candidate" = "google-chrome-stable" ] || [ "$candidate" = "google-chrome" ]; then
                      browser_flag="--browser=chrome"
                    fi
                    break
                  fi
                done

                if [ -z "$browser_executable" ]; then
                  echo "playwright MCP: no supported browser in PATH (google-chrome-stable, google-chrome, chromium, chromium-browser)." >&2
                  echo "playwright MCP: install one of those browsers to avoid browser_install downloads." >&2
                  exit 1
                fi

                exec ${lib.getExe' pkgs.nodejs "npx"} \
                  -y \
                  ${meta.package} \
                  "--executable-path=$browser_executable" \
                  ''${browser_flag:+$browser_flag} \
                  "$@"
              '';
            in
            {
              command = "${wrapper}/bin/playwright-mcp-wrapper";
              args = meta.args or [ ];
            }
            // timeouts
          else if name == "chrome-devtools" then
            let
              wrapper = pkgs.writeShellScriptBin "chrome-devtools-mcp-wrapper" ''
                set -euo pipefail

                browser_executable=""

                for candidate in google-chrome-stable google-chrome chromium chromium-browser; do
                  if command -v "$candidate" >/dev/null 2>&1; then
                    browser_executable="$(command -v "$candidate")"
                    break
                  fi
                done

                if [ -z "$browser_executable" ]; then
                  echo "chrome-devtools MCP: no supported browser in PATH (google-chrome-stable, google-chrome, chromium, chromium-browser)." >&2
                  echo "chrome-devtools MCP: install one of those browsers or use --browserUrl/--wsEndpoint to attach to an existing debug session." >&2
                  exit 1
                fi

                exec ${lib.getExe' pkgs.nodejs "npx"} \
                  -y \
                  ${meta.package} \
                  "--executablePath=$browser_executable" \
                  "$@"
              '';
            in
            {
              command = "${wrapper}/bin/chrome-devtools-mcp-wrapper";
              args = meta.args or [ ];
            }
            // timeouts
          else
            {
              command = "${lib.getExe' pkgs.nodejs "npx"}";
              args = [
                "-y"
                meta.package
              ]
              ++ (meta.args or [ ]);
            }
            // timeouts;
      };
    in
    handlers.${meta.source}
      or (throw "Unknown MCP source type: ${meta.source}. Valid: ${toString (lib.attrNames handlers)}");

  # Build config for a single server (public API for advanced use cases)
  # mkServer :: Pkgs -> String -> AttrSet
  mkServer =
    pkgs: name:
    let
      mcpPkgs = inputs.mcp-servers-nix.packages.${pkgs.stdenv.hostPlatform.system};
    in
    (mkServerConfig { inherit pkgs mcpPkgs; } name) // { type = "stdio"; };

  # Build configs for a list of servers (simplified API for consumers)
  # mkServers :: Pkgs -> [String] -> AttrSet
  mkServers =
    pkgs: enabled:
    let
      # Validate all requested servers exist (right = valid, wrong = invalid)
      inherit (lib.partition (name: serverCatalog ? ${name}) enabled) right wrong;
      catalogNames = lib.concatStringsSep ", " (lib.attrNames serverCatalog);
      result = lib.genAttrs right (mkServer pkgs);
    in
    if wrong != [ ] then
      lib.warn "Unknown MCP server(s): ${lib.concatStringsSep ", " wrong}. Valid: ${catalogNames}" result
    else
      result;

in
{
  # ════════════════════════════════════════════════════════════════════════════
  # Expose library via flake.lib.mcp (accessed via config.flake.lib.mcp)
  # ════════════════════════════════════════════════════════════════════════════
  flake.lib.mcp = {
    inherit
      serverCatalog
      mkServer
      mkServers
      ;
    defaultTimeout = defaultTimeoutSec;
  };

}

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
    npx = [ "timeout" ];
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

    # ──────────────────────────────────────────────────────────────────────────
    # NPX packages (fetched at runtime)
    # ──────────────────────────────────────────────────────────────────────────
    deepwiki = {
      source = "npx";
      package = "mcp-deepwiki@latest";
    };
  };

  defaultTimeout = 10000;

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
              startup_timeout_ms = defaultTimeout;
            }
          else
            {
              command = binPath;
              args = [ ];
              startup_timeout_ms = defaultTimeout;
            };

        sse = {
          command = "${lib.getExe' pkgs.nodejs "npx"}";
          args = [
            "mcp-remote"
            meta.url
          ];
          startup_timeout_ms = meta.timeout or defaultTimeout;
        };

        npx = {
          command = "${lib.getExe' pkgs.nodejs "npx"}";
          args = [
            "-y"
            meta.package
          ];
          startup_timeout_ms = meta.timeout or defaultTimeout;
        };
      };
    in
    handlers.${meta.source}
      or (throw "Unknown MCP source type: ${meta.source}. Valid: ${toString (lib.attrNames handlers)}");

  # Build configs for a list of servers (simplified API for consumers)
  # mkServers :: Pkgs -> [String] -> AttrSet
  mkServers =
    pkgs: enabled:
    let
      mcpPkgs = inputs.mcp-servers-nix.packages.${pkgs.stdenv.hostPlatform.system};

      # Validate all requested servers exist (right = valid, wrong = invalid)
      inherit (lib.partition (name: serverCatalog ? ${name}) enabled) right wrong;
      catalogNames = lib.concatStringsSep ", " (lib.attrNames serverCatalog);

      result = lib.genAttrs right (
        name: (mkServerConfig { inherit pkgs mcpPkgs; } name) // { type = "stdio"; }
      );
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
      defaultTimeout
      mkServers
      ;
  };

}

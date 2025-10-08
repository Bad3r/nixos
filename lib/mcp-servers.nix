/*
  Centralized definitions and selection helpers for Model Context Protocol (MCP)
  servers used across multiple agents.

  Usage patterns:
    - Import the module and call `select` to obtain full server configurations
      (including `type`).
    - Use `selectWithoutType` when the consumer expects TOML-only payloads (for
      example Codex) that omit the `type` key.
    - Pass booleans to toggle servers, strings to pick a named variant, or an
      attrset with `variant` plus override keys to tweak command/args.

  Example:
    let
      mcp = import ../../lib/mcp-servers.nix {
        inherit lib pkgs config;
      };
    in
    mcp.select {
      sequential-thinking = true;
      context7 = true;
      deepwiki = { variant = "http"; startup_timeout_ms = 90000; };
    };
*/
{
  lib,
  pkgs,
  config,
  defaultTimeoutMs ? 60000,
  defaultVariants ? { },
  ...
}:

let
  mkStdIo = command: args: {
    type = "stdio";
    inherit command args;
    startup_timeout_ms = defaultTimeoutMs;
  };

  mkNpx = args: mkStdIo "npx" args;

  mkUv = args: mkStdIo "uvx" args;

  context7ApiKeyPath = config.sops.secrets."context7/api-key".path;

  context7Wrapper = pkgs.writeShellApplication {
    name = "context7-mcp";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.nodejs
    ];
    text = ''
      set -euo pipefail
      if [ ! -r "${context7ApiKeyPath}" ]; then
        echo "context7-mcp: missing API key at ${context7ApiKeyPath}" >&2
        exit 1
      fi
      api_key=$(tr -d '\n' < "${context7ApiKeyPath}")
      exec npx -y @upstash/context7-mcp --api-key "$api_key" "$@"
    '';
  };

  mkNpxPackage =
    name:
    mkNpx [
      "-y"
      name
    ];

  mkNpxRemote =
    url:
    mkNpx [
      "mcp-remote"
      url
    ];

  groupedCatalog = {
    core = {
      sequential-thinking = {
        default = "stdio";
        variants = {
          stdio = mkNpxPackage "@modelcontextprotocol/server-sequential-thinking";
        };
      };

      memory = {
        default = "stdio";
        variants = {
          stdio = mkNpxPackage "@modelcontextprotocol/server-memory";
        };
      };

      time = {
        default = "stdio";
        variants = {
          stdio = mkUv [ "mcp-server-time" ];
        };
      };
    };

    cloudflare = {
      cfdocs = {
        default = "stdio";
        variants = {
          stdio = mkNpxRemote "https://docs.mcp.cloudflare.com/sse";
        };
      };

      cfbuilds = {
        default = "stdio";
        variants = {
          stdio = mkNpxRemote "https://builds.mcp.cloudflare.com/sse";
        };
      };

      cfobservability = {
        default = "stdio";
        variants = {
          stdio = mkNpxRemote "https://observability.mcp.cloudflare.com/sse";
        };
      };

      cfbindings = {
        default = "stdio";
        variants = {
          stdio = mkNpxRemote "https://bindings.mcp.cloudflare.com/sse";
        };
      };

      cfradar = {
        default = "stdio";
        variants = {
          stdio = mkNpxRemote "https://radar.mcp.cloudflare.com/sse";
        };
      };

      cfcontainers = {
        default = "stdio";
        variants = {
          stdio = mkNpxRemote "https://containers.mcp.cloudflare.com/sse";
        };
      };

      cfbrowser = {
        default = "stdio";
        variants = {
          stdio = mkNpxRemote "https://browser.mcp.cloudflare.com/sse";
        };
      };

      cfgraphql = {
        default = "stdio";
        variants = {
          stdio = mkNpxRemote "https://graphql.mcp.cloudflare.com/sse";
        };
      };
    };

    external = {
      deepwiki = {
        default = "remote";
        variants = {
          remote = mkNpxRemote "https://mcp.deepwiki.com/mcp";
          http = {
            type = "http";
            url = "https://mcp.deepwiki.com/mcp";
            startup_timeout_ms = defaultTimeoutMs;
          };
        };
      };

      context7 = {
        default = "stdio";
        variants = {
          stdio = {
            type = "stdio";
            command = "${context7Wrapper}/bin/context7-mcp";
            args = [ ];
            startup_timeout_ms = defaultTimeoutMs;
          };
        };
      };
    };
  };

  flatServerCatalog = builtins.foldl' (acc: groupName: acc // groupedCatalog.${groupName}) { } (
    lib.attrNames groupedCatalog
  );

  catalogHas = name: builtins.hasAttr name flatServerCatalog;

  getServerEntry =
    name:
    if catalogHas name then
      flatServerCatalog.${name}
    else
      builtins.throw "Unknown MCP server `" + name + "` requested; update modules/lib/mcp-servers.nix.";

  defaultVariantFor =
    name:
    let
      entry = getServerEntry name;
      userDefault = lib.attrByPath [ name ] null defaultVariants;
    in
    if userDefault != null then
      userDefault
    else
      entry.default or (lib.head (lib.attrNames entry.variants));

  getVariant =
    name: variant:
    let
      entry = getServerEntry name;
    in
    if builtins.hasAttr variant entry.variants then
      entry.variants.${variant}
    else
      let
        known = lib.concatStringsSep ", " (lib.attrNames entry.variants);
      in
      builtins.throw (
        "Unknown variant `" + variant + "` for MCP server `" + name + "`. Known variants: " + known
      );

  resolvedServers =
    selections:
    let
      resolveValue =
        name: value:
        if value == null || (lib.isBool value && !value) then
          null
        else if lib.isBool value && value then
          getVariant name (defaultVariantFor name)
        else if lib.isString value then
          getVariant name value
        else if lib.isAttrs value then
          if catalogHas name then
            let
              variant = lib.attrByPath [ "variant" ] value (defaultVariantFor name);
              overrides = lib.removeAttrs value [ "variant" ];
              base = getVariant name variant;
            in
            lib.recursiveUpdate base overrides
          else
            value
        else
          let
            valueType = builtins.typeOf value;
          in
          builtins.throw (
            "Unsupported selection value for MCP server `"
            + name
            + "` (type "
            + valueType
            + "). Expected bool, string, or attr set."
          );
    in
    lib.filterAttrs (_: v: v != null) (lib.mapAttrs resolveValue selections);

  dropType = servers: lib.mapAttrs (_: server: lib.removeAttrs server [ "type" ]) servers;

in
{
  catalogGroups = groupedCatalog;
  serverCatalog = flatServerCatalog;
  definitions = lib.mapAttrs (_: entry: entry.variants) flatServerCatalog;

  select = resolvedServers;
  selectWithoutType = selections: dropType (resolvedServers selections);
  removeType = dropType;
}

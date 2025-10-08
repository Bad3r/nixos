{
  lib,
  defaultTimeoutMs ? 60000,
  defaultVariants ? { },
  ...
}:

let
  mkNpx = args: {
    type = "stdio";
    command = "npx";
    inherit args;
    startup_timeout_ms = defaultTimeoutMs;
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

  serverCatalog = {
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
        stdio = {
          type = "stdio";
          command = "uvx";
          args = [ "mcp-server-time" ];
          startup_timeout_ms = defaultTimeoutMs;
        };
      };
    };

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
  };

  catalogHas = name: builtins.hasAttr name serverCatalog;

  getServerEntry =
    name:
    if catalogHas name then
      serverCatalog.${name}
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
          builtins.throw "Unsupported selection value for MCP server `" + name + "`.";
    in
    lib.filterAttrs (_: v: v != null) (lib.mapAttrs resolveValue selections);

  dropType = servers: lib.mapAttrs (_: server: lib.removeAttrs server [ "type" ]) servers;

in
{
  inherit serverCatalog;
  definitions = lib.mapAttrs (_: entry: entry.variants) serverCatalog;

  select = resolvedServers;
  selectWithoutType = selections: dropType (resolvedServers selections);
  removeType = dropType;
}

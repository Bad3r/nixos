{
  config,
  lib,
  inputs,
  ...
}:
let
  rawServers = config.flake.lib.agents._internal.mcp.raw;

  validSources = [
    "nix"
    "http"
    "sse"
    "npx"
  ];

  validClients = [
    "claude"
    "codex"
  ];

  docClientOrder = [
    "codex"
    "claude"
  ];

  clientLabels = {
    claude = "Claude Code";
    codex = "Codex";
  };

  requiredFields = {
    nix = [ "package" ];
    http = [ "url" ];
    sse = [ "url" ];
    npx = [ "package" ];
  };

  optionalFields = {
    nix = [ "secretEnvVar" ];
    http = [ "timeout" ];
    sse = [ "timeout" ];
    npx = [
      "timeout"
      "args"
    ];
  };

  validateAllowedFields =
    context: allowedFields: attrs:
    let
      extraFields = lib.filter (field: !(lib.elem field allowedFields)) (lib.attrNames attrs);
    in
    if extraFields == [ ] then
      attrs
    else
      throw "Agent MCP ${context} has unknown fields: ${lib.concatStringsSep ", " extraFields}";

  validateNonEmptyString =
    serverName: field: value:
    if builtins.isString value && value != "" then
      value
    else
      throw "Agent MCP server '${serverName}' requires non-empty string field '${field}'";

  validateDocs =
    serverName: docs:
    let
      validatedDocs = validateAllowedFields "'${serverName}'.docs'" [
        "primaryUse"
        "accessNotes"
        "example"
      ] docs;
      requiredDocFields = [
        "primaryUse"
        "accessNotes"
        "example"
      ];
      missingFields = lib.filter (field: !(validatedDocs ? ${field})) requiredDocFields;
    in
    if missingFields != [ ] then
      throw "Agent MCP server '${serverName}' missing docs fields: ${lib.concatStringsSep ", " missingFields}"
    else
      lib.mapAttrs (field: value: validateNonEmptyString serverName "docs.${field}" value) validatedDocs;

  validateClients =
    serverName: clients:
    let
      normalizedClients = builtins.sort builtins.lessThan clients;
      unknownClients = lib.filter (client: !(lib.elem client validClients)) normalizedClients;
    in
    if !builtins.isList clients then
      throw "Agent MCP server '${serverName}' requires list field 'clients'"
    else if !lib.all builtins.isString normalizedClients then
      throw "Agent MCP server '${serverName}' requires all 'clients' entries to be strings"
    else if unknownClients != [ ] then
      throw ''
        Agent MCP server '${serverName}' has unknown clients: ${lib.concatStringsSep ", " unknownClients}

        Valid clients: ${lib.concatStringsSep ", " validClients}
      ''
    else
      lib.unique normalizedClients;

  validateServer =
    serverName: rawServer:
    let
      source =
        rawServer.source or (throw "Agent MCP server '${serverName}' missing required field 'source'");
      validSource = lib.elem source validSources;
      required = requiredFields.${source} or [ ];
      optional = optionalFields.${source} or [ ];
      allowedFields = [
        "source"
        "clients"
        "docs"
      ]
      ++ required
      ++ optional;
      validatedServer = validateAllowedFields "'${serverName}'" allowedFields rawServer;
      missingFields = lib.filter (field: !(validatedServer ? ${field})) (
        [
          "clients"
          "docs"
        ]
        ++ required
      );
    in
    if !validSource then
      throw "Agent MCP server '${serverName}' has invalid source '${source}'. Valid: ${toString validSources}"
    else if missingFields != [ ] then
      throw "Agent MCP server '${serverName}' (${source}) missing required fields: ${toString missingFields}"
    else
      validatedServer
      // {
        name = serverName;
        clients = validateClients serverName validatedServer.clients;
        docs = validateDocs serverName validatedServer.docs;
      };

  validatedServers = lib.mapAttrs validateServer rawServers;

  defaultTimeoutSec = 60;

  mkTimeouts = sec: {
    startup_timeout_sec = sec;
    startup_timeout_ms = sec * 1000;
  };

  mkServerConfig =
    { pkgs, mcpPkgs }:
    name:
    let
      meta =
        validatedServers.${name}
          or (throw "Unknown MCP server: ${name}. Valid: ${toString (lib.attrNames validatedServers)}");

      timeouts = mkTimeouts (meta.timeout or defaultTimeoutSec);

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
                  if [ -r "$secret_path" ] && [ -s "$secret_path" ]; then
                    # Context7 supports unauthenticated access; export auth only when the optional secret exists.
                    if ! secret_value="$(tr -d '\n' < "$secret_path")"; then
                      echo "Failed to read Context7 secret from $secret_path" >&2
                      exit 1
                    fi
                    export ${meta.secretEnvVar}="$secret_value"
                  fi
                  exec ${binPath} "$@"
                '';
              };
            in
            {
              command = "${wrapper}/bin/${name}-wrapper";
              args = [ ];
              type = "stdio";
            }
            // timeouts
          else
            {
              command = binPath;
              args = [ ];
              type = "stdio";
            }
            // timeouts;

        http = {
          inherit (meta) url;
          type = "http";
        }
        // timeouts;

        sse = {
          command = "${lib.getExe' pkgs.nodejs "npx"}";
          args = [
            "mcp-remote"
            meta.url
          ];
          type = "stdio";
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
              type = "stdio";
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
              type = "stdio";
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
              type = "stdio";
            }
            // timeouts;
      };
    in
    handlers.${meta.source}
      or (throw "Unknown MCP source type: ${meta.source}. Valid: ${toString (lib.attrNames handlers)}");

  mkServer =
    pkgs: name:
    let
      mcpPkgs = inputs.mcp-servers-nix.packages.${pkgs.stdenv.hostPlatform.system};
    in
    mkServerConfig { inherit pkgs mcpPkgs; } name;

  mkServers =
    pkgs: enabled:
    let
      inherit (lib.partition (name: validatedServers ? ${name}) enabled) right wrong;
      catalogNames = lib.concatStringsSep ", " (lib.attrNames validatedServers);
      result = lib.genAttrs right (mkServer pkgs);
    in
    if wrong != [ ] then
      lib.warn "Unknown MCP server(s): ${lib.concatStringsSep ", " wrong}. Valid: ${catalogNames}" result
    else
      result;

  clientServerNames =
    client:
    lib.filter (name: lib.elem client validatedServers.${name}.clients) (
      builtins.sort builtins.lessThan (lib.attrNames validatedServers)
    );

  compiledClients = lib.genAttrs validClients (client: {
    names = clientServerNames client;
    servers = pkgs: mkServers pkgs (clientServerNames client);
  });

  renderClientList =
    clients:
    let
      orderedClients = lib.filter (client: lib.elem client clients) docClientOrder;
    in
    if orderedClients == [ ] then
      "None"
    else
      lib.concatStringsSep ", " (map (client: clientLabels.${client}) orderedClients);

  escapeTableCell = value: lib.replaceStrings [ "|" "\n" ] [ "\\|" " " ] value;

  padRight =
    width: value:
    let
      padding = width - lib.stringLength value;
    in
    value + lib.concatStrings (builtins.genList (_: " ") (if padding > 0 then padding else 0));

  tableHeaders = [
    "Tool"
    "Default Clients"
    "Primary Use"
    "Access Notes"
    "Example"
  ];

  renderReferenceMarkdown =
    let
      serverNames = builtins.sort builtins.lessThan (lib.attrNames validatedServers);
      rows = map (
        name:
        let
          server = validatedServers.${name};
        in
        [
          "`${escapeTableCell server.name}`"
          (escapeTableCell (renderClientList server.clients))
          (escapeTableCell server.docs.primaryUse)
          (escapeTableCell server.docs.accessNotes)
          (escapeTableCell server.docs.example)
        ]
      ) serverNames;
      allRows = [ tableHeaders ] ++ rows;
      columnCount = builtins.length tableHeaders;
      columnWidths = builtins.genList (
        index: lib.foldl' lib.max 0 (map (row: lib.stringLength (builtins.elemAt row index)) allRows)
      ) columnCount;
      renderTableRow =
        cells:
        let
          paddedCells = builtins.genList (
            index: padRight (builtins.elemAt columnWidths index) (builtins.elemAt cells index)
          ) columnCount;
        in
        "| " + lib.concatStringsSep " | " paddedCells + " |";
      renderRule =
        "| "
        + lib.concatStringsSep " | " (
          map (width: lib.concatStrings (builtins.genList (_: "-") width)) columnWidths
        )
        + " |";
      renderedRows = map renderTableRow rows;
    in
    lib.concatStringsSep "\n" (
      [
        "# MCP Tools"
        ""
        "Generated from `flake.lib.agents.mcp.servers`. `Default Clients` shows which Nix-managed clients enable each server out of the box. Use `/mcp` to inspect current runtime availability."
        ""
        (renderTableRow tableHeaders)
        renderRule
      ]
      ++ renderedRows
      ++ [ "" ]
    );
in
{
  options.flake.lib.agents = {
    _internal.mcp.raw = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Canonical raw MCP server specifications compiled into public agent outputs.";
    };

    mcp = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Compiled MCP registries, client profiles, docs, and runtime builders.";
    };
  };

  config.flake.lib.agents.mcp = {
    servers = validatedServers;
    clients = compiledClients;
    docs.referenceMarkdown = renderReferenceMarkdown;
    inherit
      defaultTimeoutSec
      mkServer
      mkServers
      ;
  };
}

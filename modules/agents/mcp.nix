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
    "npx"
    "app"
  ];

  registry = import ./_registry.nix { inherit lib; };
  inherit (registry) validClients;
  validateAllowedFields = registry.validateAllowedFields "MCP";
  validateNonEmptyString = registry.validateNonEmptyString "MCP server";
  validateClients = registry.validateClients "MCP server";

  docClientOrder = [
    "codex"
    "claude"
    "antigravity"
  ];

  clientLabels = {
    antigravity = "Antigravity";
    claude = "Claude Code";
    codex = "Codex";
  };

  validNetworkModes = [
    "limited"
    "full"
  ];

  requiredFields = {
    nix = [ "package" ];
    http = [ "url" ];
    npx = [ "package" ];
    app = [
      "app"
      "program"
    ];
  };

  optionalFields = {
    nix = [ "secretEnv" ];
    http = [
      "timeout"
      "secretHeader"
    ];
    npx = [
      "timeout"
      "args"
      "app"
    ];
    app = [
      "timeout"
      "toolTimeout"
    ];
  };

  validateDocs =
    serverName: docs:
    let
      validatedDocs = validateAllowedFields "'${serverName}'.docs" [
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

  validateStringList =
    serverName: field: values:
    if !builtins.isList values then
      throw "Agent MCP server '${serverName}' requires list field '${field}'"
    else if !lib.all (value: builtins.isString value && value != "") values then
      throw "Agent MCP server '${serverName}' requires all '${field}' entries to be non-empty strings"
    else
      builtins.sort builtins.lessThan (lib.unique values);

  validateNetwork =
    serverName: network:
    let
      validatedNetwork =
        if builtins.isAttrs network then
          validateAllowedFields "'${serverName}'.network" [
            "mode"
            "allowedDomains"
          ] network
        else
          throw "Agent MCP server '${serverName}' requires attrset field 'network'";
      mode = validatedNetwork.mode or "limited";
      allowedDomains =
        if validatedNetwork ? allowedDomains then
          validateStringList serverName "network.allowedDomains" validatedNetwork.allowedDomains
        else
          [ ];
    in
    if lib.elem mode validNetworkModes then
      {
        inherit mode allowedDomains;
      }
    else
      throw "Agent MCP server '${serverName}' has invalid network.mode '${mode}'. Valid: ${toString validNetworkModes}";

  validateSecretRelativePath =
    serverName: field: relativePath:
    if lib.hasPrefix "/" relativePath || lib.hasInfix ".." relativePath then
      throw "Agent MCP server '${serverName}' ${field}.relativePath must be a clean XDG_DATA_HOME-relative path"
    else
      relativePath;

  validateSecretHeader =
    serverName: secretHeader:
    let
      validated =
        if builtins.isAttrs secretHeader then
          validateAllowedFields "'${serverName}'.secretHeader" [
            "name"
            "relativePath"
            "prefix"
          ] secretHeader
        else
          throw "Agent MCP server '${serverName}' requires attrset field 'secretHeader'";
      missingFields = lib.filter (field: !(validated ? ${field})) [
        "name"
        "relativePath"
      ];
      headerName = validateNonEmptyString serverName "secretHeader.name" validated.name;
      relativePath = validateNonEmptyString serverName "secretHeader.relativePath" validated.relativePath;
    in
    if missingFields != [ ] then
      throw "Agent MCP server '${serverName}' missing secretHeader fields: ${lib.concatStringsSep ", " missingFields}"
    else if builtins.match ".*[\r\n].*" headerName != null then
      throw "Agent MCP server '${serverName}' secretHeader.name must not contain newlines"
    else if validated ? prefix && !builtins.isString validated.prefix then
      throw "Agent MCP server '${serverName}' secretHeader.prefix must be a string"
    else if validated ? prefix && builtins.match ".*[\r\n].*" validated.prefix != null then
      throw "Agent MCP server '${serverName}' secretHeader.prefix must not contain newlines"
    else
      {
        name = headerName;
        relativePath = validateSecretRelativePath serverName "secretHeader" relativePath;
      }
      // lib.optionalAttrs (validated ? prefix) {
        inherit (validated) prefix;
      };

  validateSecretEnv =
    serverName: secretEnv:
    let
      validated =
        if builtins.isAttrs secretEnv then
          validateAllowedFields "'${serverName}'.secretEnv" [
            "name"
            "relativePath"
          ] secretEnv
        else
          throw "Agent MCP server '${serverName}' requires attrset field 'secretEnv'";
      missingFields = lib.filter (field: !(validated ? ${field})) [
        "name"
        "relativePath"
      ];
      envName = validateNonEmptyString serverName "secretEnv.name" validated.name;
      relativePath = validateNonEmptyString serverName "secretEnv.relativePath" validated.relativePath;
    in
    if missingFields != [ ] then
      throw "Agent MCP server '${serverName}' missing secretEnv fields: ${lib.concatStringsSep ", " missingFields}"
    else if builtins.match "[A-Za-z_][A-Za-z0-9_]*" envName == null then
      throw "Agent MCP server '${serverName}' secretEnv.name must be a shell variable name"
    else
      {
        name = envName;
        relativePath = validateSecretRelativePath serverName "secretEnv" relativePath;
      };

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
        "network"
        "disabled"
        "direct"
        "autoApprove"
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
      direct = validatedServer.direct or false;
      autoApprove = validatedServer.autoApprove or false;
    in
    if !validSource then
      throw "Agent MCP server '${serverName}' has invalid source '${source}'. Valid: ${toString validSources}"
    else if missingFields != [ ] then
      throw "Agent MCP server '${serverName}' (${source}) missing required fields: ${toString missingFields}"
    else if
      validatedServer ? app
      && !(
        config.flake.lib.nixos.hasApp validatedServer.app
        || config.flake.lib.nixos.hasBrowser validatedServer.app
      )
    then
      throw "Agent MCP server '${serverName}' names app '${validatedServer.app}', which has no flake.nixosModules.apps or browsers entry"
    else if validatedServer ? disabled && !builtins.isBool validatedServer.disabled then
      throw "Agent MCP server '${serverName}' requires boolean field 'disabled'"
    else if validatedServer ? direct && !builtins.isBool validatedServer.direct then
      throw "Agent MCP server '${serverName}' requires boolean field 'direct'"
    else if validatedServer ? autoApprove && !builtins.isBool validatedServer.autoApprove then
      throw "Agent MCP server '${serverName}' requires boolean field 'autoApprove'"
    else if autoApprove && !direct then
      throw "Agent MCP server '${serverName}' sets 'autoApprove = true' without 'direct = true'"
    else if direct && (validatedServer.disabled or false) then
      throw "Agent MCP server '${serverName}' cannot combine 'direct = true' with 'disabled = true'"
    else if direct && (validatedServer ? secretHeader) then
      throw "Agent MCP server '${serverName}' cannot combine 'direct = true' with 'secretHeader'"
    else
      validatedServer
      // {
        name = serverName;
        disabled = validatedServer.disabled or false;
        inherit direct autoApprove;
        clients = validateClients serverName validatedServer.clients;
        docs = validateDocs serverName validatedServer.docs;
        network =
          if validatedServer ? network then
            validateNetwork serverName validatedServer.network
          else
            {
              mode = "limited";
              allowedDomains = [ ];
            };
      }
      // lib.optionalAttrs (validatedServer ? secretHeader) {
        secretHeader = validateSecretHeader serverName validatedServer.secretHeader;
      }
      // lib.optionalAttrs (validatedServer ? secretEnv) {
        secretEnv = validateSecretEnv serverName validatedServer.secretEnv;
      };

  validatedServers = lib.mapAttrs validateServer rawServers;

  gatewayRouted = name: !validatedServers.${name}.direct;
  gatewayServerNames = lib.filter gatewayRouted (lib.attrNames validatedServers);

  defaultTimeoutSec = 60;
  defaultToolTimeoutSec = 180;

  mkTimeouts = sec: {
    startup_timeout_sec = sec;
    startup_timeout_ms = sec * 1000;
  };

  # Claude Code reads `timeout`, Codex `tool_timeout_sec`.
  mkToolTimeouts = sec: {
    tool_timeout_sec = sec;
    timeout = sec * 1000;
  };

  # An app's server exists only where the host turns the app's row on.
  enabledOn =
    osConfig: server:
    !(server ? app) || lib.attrByPath [ "programs" server.app "extended" "enable" ] false osConfig;

  mkServerConfig =
    {
      pkgs,
      mcpPkgs,
      osConfig,
    }:
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
          if meta ? secretEnv then
            let
              relativePath = lib.escapeShellArg meta.secretEnv.relativePath;
              wrapper = pkgs.writeShellApplication {
                name = "${name}-wrapper";
                runtimeInputs = [
                  pkgs.coreutils
                  pkg
                ];
                text = /* bash */ ''
                  secret_path="''${XDG_DATA_HOME:-$HOME/.local/share}"/${relativePath}
                  if [ ! -r "$secret_path" ] || [ ! -s "$secret_path" ]; then
                    fallback_path="$HOME/.local/share"/${relativePath}
                    if [ -r "$fallback_path" ] && [ -s "$fallback_path" ]; then
                      secret_path="$fallback_path"
                    fi
                  fi
                  # The secret is optional; the server starts without it.
                  if [ -r "$secret_path" ] && [ -s "$secret_path" ]; then
                    if ! secret_value="$(tr -d '\r\n' < "$secret_path")"; then
                      echo "Failed to read the ${name} MCP secret from $secret_path" >&2
                      exit 1
                    fi
                    export ${meta.secretEnv.name}="$secret_value"
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

        # `toolTimeout` may read the app's settings.
        app =
          let
            cfg = osConfig.programs.${meta.app}.extended;
            toolTimeout = if lib.isFunction meta.toolTimeout then meta.toolTimeout cfg else meta.toolTimeout;
          in
          {
            command =
              if lib.isFunction meta.program then
                meta.program cfg
              else
                lib.getExe' (cfg.finalPackage or cfg.package) meta.program;
            args = [ ];
            type = "stdio";
          }
          // timeouts
          // lib.optionalAttrs (meta ? toolTimeout) (mkToolTimeouts toolTimeout);

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

                export CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS=1
                export CHROME_DEVTOOLS_MCP_NO_UPDATE_CHECKS=1
                export NPM_CONFIG_UPDATE_NOTIFIER=false

                for arg in "$@"; do
                  if [ "$arg" = "--" ]; then
                    echo "chrome-devtools MCP: standalone -- would disable mandatory privacy options." >&2
                    exit 2
                  fi
                done

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
                  "$@" \
                  --no-usage-statistics \
                  --no-performance-crux
              '';
            in
            {
              command = "${wrapper}/bin/chrome-devtools-mcp-wrapper";
              args = meta.args or [ ];
              type = "stdio";
            }
            // timeouts
          else if name == "firefox" then
            let
              cfg = osConfig.programs.${meta.app}.extended;
              browser = lib.getExe (cfg.finalPackage or cfg.package);
              geckodriver = osConfig.programs.geckodriver.extended;
              driver =
                if geckodriver.enable then
                  geckodriver.finalPackage or geckodriver.package
                else
                  throw "Agent MCP server '${name}' needs the geckodriver app row on";
              wrapper = pkgs.writeShellScriptBin "firefox-mcp-wrapper" ''
                set -euo pipefail

                # The privileged, prefs, and bidi modules need this in Firefox's own environment.
                export MOZ_REMOTE_ALLOW_SYSTEM_ACCESS=1
                export MOZ_CRASHREPORTER_DISABLE=1
                export SE_AVOID_STATS=true
                export DO_NOT_TRACK=1
                export NPM_CONFIG_UPDATE_NOTIFIER=false

                # The server searches PATH for geckodriver before it downloads a binary.
                export PATH=${lib.makeBinPath [ driver ]}:"$PATH"

                exec ${lib.getExe' pkgs.nodejs "npx"} \
                  -y \
                  ${meta.package} \
                  "--firefox-path=${browser}" \
                  "$@"
              '';
            in
            {
              command = "${wrapper}/bin/firefox-mcp-wrapper";
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
    { pkgs, osConfig }:
    name:
    let
      mcpPkgs = inputs.mcp-servers-nix.packages.${pkgs.stdenv.hostPlatform.system};
    in
    mkServerConfig { inherit pkgs mcpPkgs osConfig; } name;

  mkServers =
    args: enabled:
    let
      inherit (lib.partition (name: validatedServers ? ${name}) enabled) right wrong;
      catalogNames = lib.concatStringsSep ", " (lib.attrNames validatedServers);
      result = lib.genAttrs right (mkServer args);
    in
    if wrong != [ ] then
      lib.warn "Unknown MCP server(s): ${lib.concatStringsSep ", " wrong}. Valid: ${catalogNames}" result
    else
      result;

  codemodePkgFor =
    pkgs: osConfig:
    let
      hasEnable = lib.hasAttrByPath [ "programs" "mcp-codemode" "extended" "enable" ] osConfig;
      enabled = lib.attrByPath [ "programs" "mcp-codemode" "extended" "enable" ] false osConfig;
      configured = lib.attrByPath [ "programs" "mcp-codemode" "extended" "package" ] null osConfig;
    in
    if hasEnable && !enabled then
      throw "Agent MCP codemode gateway needs the mcp-codemode app row on (programs.\"mcp-codemode\".extended.enable = true)"
    else if configured != null then
      configured
    else
      pkgs.callPackage ../../packages/mcp-codemode { };

  mkClientManifestData =
    {
      client,
      pkgs,
      osConfig,
    }:
    enabled:
    let
      codemodeNames = lib.filter gatewayRouted enabled;
      rawServers = mkServers { inherit pkgs osConfig; } codemodeNames;
      servers = lib.mapAttrs (
        name: server:
        let
          meta = validatedServers.${name};
          baseFields = {
            enabled = !meta.disabled;
            primaryUse = meta.docs.primaryUse;
            accessNotes = meta.docs.accessNotes;
            startupTimeoutSec = server.startup_timeout_sec or defaultTimeoutSec;
            toolTimeoutSec =
              server.tool_timeout_sec or (lib.max defaultToolTimeoutSec (server.startup_timeout_sec or 0));
          };
        in
        if server ? url then
          baseFields
          // {
            transport = "http";
            inherit (server) url;
          }
          // lib.optionalAttrs (meta ? secretHeader) {
            inherit (meta) secretHeader;
          }
        else
          baseFields
          // {
            transport = "stdio";
            inherit (server) command;
            args = server.args or [ ];
          }
      ) rawServers;
    in
    {
      inherit client servers;
    };

  mkDirectClientServers =
    client:
    {
      pkgs,
      osConfig,
      serverOverrides ? { },
    }:
    directNames:
    let
      rawDirect = mkServers { inherit pkgs osConfig; } directNames;
      mergedDirect = lib.mapAttrs (name: server: server // (serverOverrides.${name} or { })) rawDirect;
    in
    if client == "codex" then
      lib.mapAttrs (
        name: server:
        builtins.removeAttrs server [
          "type"
          "startup_timeout_ms"
          "timeout"
        ]
        // lib.optionalAttrs validatedServers.${name}.autoApprove {
          default_tools_approval_mode = "approve";
        }
      ) mergedDirect
    else if client == "antigravity" then
      lib.mapAttrs (
        _name: server:
        let
          effectiveTimeoutSec = lib.max (server.startup_timeout_sec or 0) (server.tool_timeout_sec or 0);
          timeoutAttr = lib.optionalAttrs (effectiveTimeoutSec > 180) {
            timeoutSeconds = effectiveTimeoutSec;
          };
        in
        if server ? url then
          { serverUrl = server.url; } // timeoutAttr
        else
          builtins.removeAttrs server [
            "type"
            "startup_timeout_sec"
            "startup_timeout_ms"
            "tool_timeout_sec"
            "timeout"
          ]
          // timeoutAttr
      ) mergedDirect
    else
      lib.mapAttrs (
        _name: server:
        builtins.removeAttrs server [
          "startup_timeout_sec"
          "tool_timeout_sec"
        ]
      ) mergedDirect;

  mkClientServers =
    client:
    {
      pkgs,
      osConfig,
      serverOverrides ? { },
    }:
    enabled:
    let
      partitioned = lib.partition gatewayRouted enabled;
      directNames = partitioned.wrong;
      codemodeNames = partitioned.right;
      directEntries = mkDirectClientServers client {
        inherit
          pkgs
          osConfig
          serverOverrides
          ;
      } directNames;
      codemodeEntry =
        if codemodeNames == [ ] then
          { }
        else
          let
            manifestData = mkClientManifestData {
              inherit client pkgs osConfig;
            } codemodeNames;
            manifestFile = pkgs.writeText "${client}-codemode-manifest.json" (builtins.toJSON manifestData);
            codemodeBin = lib.getExe (codemodePkgFor pkgs osConfig);
            envVars = [
              "MCP_CODEMODE_ENABLE"
              "MCP_CODEMODE_DISABLE"
              "XDG_STATE_HOME"
              "XDG_DATA_HOME"
            ];
            maxToolTimeoutSec = lib.foldl' lib.max defaultToolTimeoutSec (
              map (name: manifestData.servers.${name}.toolTimeoutSec) codemodeNames
            );
            # Leave 15 s of headroom below the client/REPL timeout so sandbox teardown
            # and structured timeout errors flush before the client aborts the tool call.
            codemodeTimeoutSec = lib.max defaultTimeoutSec (maxToolTimeoutSec - 15);
            baseEntry = {
              command = codemodeBin;
              args = [
                "serve"
                "--manifest"
                "${manifestFile}"
                "--timeout"
                (toString codemodeTimeoutSec)
              ];
            };
          in
          {
            codemode =
              if client == "codex" then
                baseEntry
                // {
                  startup_timeout_sec = defaultTimeoutSec;
                  tool_timeout_sec = maxToolTimeoutSec;
                  env_vars = envVars;
                }
              else if client == "antigravity" then
                baseEntry
                // lib.optionalAttrs (maxToolTimeoutSec > 180) {
                  timeoutSeconds = maxToolTimeoutSec;
                }
              else
                baseEntry
                // {
                  type = "stdio";
                  startup_timeout_ms = defaultTimeoutSec * 1000;
                  timeout = maxToolTimeoutSec * 1000;
                };
          };
    in
    directEntries // codemodeEntry;

  clientServerNames =
    client:
    lib.filter (name: lib.elem client validatedServers.${name}.clients) (
      builtins.sort builtins.lessThan (lib.attrNames validatedServers)
    );

  compiledClients = lib.genAttrs validClients (
    client:
    let
      names = clientServerNames client;
      enabledNames = osConfig: lib.filter (name: enabledOn osConfig validatedServers.${name}) names;
    in
    {
      inherit names enabledNames;
      manifest =
        { pkgs, osConfig }:
        mkClientManifestData {
          inherit client pkgs osConfig;
        } (enabledNames osConfig);
      servers =
        {
          pkgs,
          osConfig,
          serverOverrides ? { },
        }:
        mkClientServers client {
          inherit
            pkgs
            osConfig
            serverOverrides
            ;
        } (enabledNames osConfig);
      # Claude Code and Antigravity approve direct MCP tools through permission rules.
      autoApproved =
        osConfig:
        lib.filter (name: validatedServers.${name}.direct && validatedServers.${name}.autoApprove) (
          enabledNames osConfig
        );
    }
  );

  renderClientList =
    server:
    let
      orderedClients = lib.filter (client: lib.elem client server.clients) docClientOrder;
      labels = lib.concatStringsSep ", " (map (client: clientLabels.${client}) orderedClients);
    in
    if orderedClients == [ ] then
      "None"
    else if server.disabled then
      "None (opt-in: ${labels})"
    else
      labels;

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
          (escapeTableCell (renderClientList server))
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
        "Generated from `flake.lib.agents.mcp.servers`. Standard servers connect through the single `codemode` gateway (`search` and `execute`), while local servers requiring client-native confirmation routing or session metadata (`node_repl`, `sbx`) register directly. `Default Clients` shows which clients include each server out of the box. Inspect `codemode` server availability via `search` (`await codemode.servers()`) or `mcp-codemode status --manifest <path>`, using the manifest store path from `~/.claude.json`, `~/.gemini/config/mcp_config.json`, or `$CODEX_HOME/config.base.toml` (`mcp-codemode status` alone prints active override entries). Project-scoped toggles (`mcp-codemode enable <server>`) apply to the directory where the command ran and its descendants; GUI clients launch outside the open workspace and require `--user`. `enable` and `disable` reject names missing from `/etc/mcp-codemode/servers.json`, which lists every `codemode`-routed server."
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
      gatewayServerNames
      mkServer
      mkServers
      ;
  };
}

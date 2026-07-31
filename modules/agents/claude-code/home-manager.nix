/*
  Package: claude-code
  Description: Anthropic's Claude Code CLI for repository-aware conversations and code generation.
  Homepage: https://docs.anthropic.com/en/docs/claude-code/overview
  Documentation: https://docs.anthropic.com/en/docs/claude-code/overview
  Repository: https://github.com/anthropics/claude-code

  Notes:
    * MCP servers configured via flake.lib.agents.mcp (modules/agents/mcp.nix)
    * Agent skills configured via flake.lib.agents.skills (modules/agents/skills.nix)
    * User-level instructions generated via flake.lib.agents.systemPrompt
      (modules/agents/system-prompt.nix)
    * Optional Context7 API key can be provisioned via SOPS at `sops.secrets."context7/api-key"`
    * Greptile plugin activation is optional and resolved during Home Manager
      activation only when the plugin is explicitly enabled.
    * LSP plugin enablement and binary installation are governed by
      programs.claude-code.extended.lspPlugins in modules/apps/claude-code.nix.
    * Additional non-LSP plugins are governed by
      programs.claude-code.extended.extraPlugins in modules/apps/claude-code.nix.
    * Blocked MCP servers, mainly the claude.ai account connectors that local
      config cannot otherwise remove, are governed by
      programs.claude-code.extended.deniedMcpServers in modules/apps/claude-code.nix.
    * `enabledPlugins` keys end with `@<marketplace>` (see
      ~/.claude/plugins/known_marketplaces.json). Default plugins assume the
      `claude-plugins-official` marketplace is registered (install once with
      `claude-plugins install anthropics/claude-plugins-official`); entries
      that reference an unregistered marketplace are silently ignored.
    * Config is split across private helpers in modules/agents/claude-code/:
        _default-settings.nix  static defaults for settings.json, .claude.json,
                               and keybindings.json
        _plugins.nix           enabledPlugins composition from osConfig
        _settings.nix          merges defaults + plugins + mcpServers
        _activation.nix        activation snippets (jq merge + optional bun install)
        _wrapper.nix           shell launcher environment and binary selection
*/

{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      renderWrapper =
        {
          installMethods,
          greptilePluginRequested,
        }:
        import ./_wrapper.nix {
          inherit
            lib
            pkgs
            installMethods
            greptilePluginRequested
            ;
          claudePkg = "/nix/store/test-claude";
          bunInstallDir = "/nix/store/test-bun";
          externalBinary = "/nix/store/test-external/bin/claude";
          greptileApiKeyPath = "/tmp/greptile/api-key";
        };
      installMethodVariants = {
        bun = {
          bun.enable = true;
          nix.enable = false;
        };
        nix = {
          bun.enable = false;
          nix.enable = true;
        };
        external = {
          bun.enable = false;
          nix.enable = false;
        };
      };
      variants = {
        "bun-greptile-false" = renderWrapper {
          installMethods = installMethodVariants.bun;
          greptilePluginRequested = false;
        };
        "bun-greptile-true" = renderWrapper {
          installMethods = installMethodVariants.bun;
          greptilePluginRequested = true;
        };
        "nix-greptile-false" = renderWrapper {
          installMethods = installMethodVariants.nix;
          greptilePluginRequested = false;
        };
        "nix-greptile-true" = renderWrapper {
          installMethods = installMethodVariants.nix;
          greptilePluginRequested = true;
        };
        "external-greptile-false" = renderWrapper {
          installMethods = installMethodVariants.external;
          greptilePluginRequested = false;
        };
        "external-greptile-true" = renderWrapper {
          installMethods = installMethodVariants.external;
          greptilePluginRequested = true;
        };
      };
      wrapperPaths = lib.mapAttrs (_: wrapper: lib.getExe wrapper.claudeWrapped) variants;
    in
    {
      checks."claude-code/wrapper-target-contract" =
        pkgs.runCommandLocal "claude-code-wrapper-target-contract"
          {
            nativeBuildInputs = [ pkgs.makeWrapper ];
          }
          ''
            mkdir -p probe/bin
            # Reproduce wrapping an existing shell launcher beside its hidden
            # binary, which creates both shell hops and the collision suffix.
            install -m 0755 ${lib.getExe pkgs.hello} probe/bin/.hello-wrapped
            makeShellWrapper "$PWD/probe/bin/.hello-wrapped" "$PWD/probe/bin/hello" \
              --inherit-argv0 --set CLAUDE_CODE_WRAPPER_PROBE 1
            wrapProgram "$PWD/probe/bin/hello" --set CLAUDE_CODE_WRAPPER_PROBE 1
            PROBE_OUTER="$PWD/probe/bin/hello"
            PROBE_INNER="$PWD/probe/bin/.hello-wrapped_"
            PROBE_TARGET="$PWD/probe/bin/.hello-wrapped"
            makeShellWrapper "$PROBE_TARGET" "$PWD/probe/bin/no-argv0" \
              --set CLAUDE_CODE_WRAPPER_PROBE 1
            for probeFile in "$PROBE_OUTER" "$PROBE_INNER" "$PWD/probe/bin/no-argv0"; do
              if [ ! -f "$probeFile" ]; then
                echo "makeWrapper did not create $probeFile" >&2
                exit 1
              fi
            done
            makeWrapper ${lib.getExe pkgs.hello} "$PWD/probe/bin/interpreter" \
              --add-flags "$PWD/probe/bin/cli.js"
            PATCH_FILE=${../../../packages/tweakcc/shell-wrapper.patch} \
              PROBE_FILE="$PROBE_OUTER" \
              PROBE_WRAPPED="$PROBE_INNER" \
              PROBE_INNER="$PROBE_INNER" \
              PROBE_TARGET="$PROBE_TARGET" \
              PROBE_NO_ARG="$PWD/probe/bin/no-argv0" \
              PROBE_INTERPRETER="$PWD/probe/bin/interpreter" \
              ${lib.getExe pkgs.nodejs} --input-type=module <<'NODE'
            import { readFileSync } from "node:fs";

            const patch = readFileSync(process.env.PATCH_FILE, "utf8");
            const wrapperPaths = ${builtins.toJSON wrapperPaths};
            const regexLiterals = patch
              .split("\n")
              .flatMap((line) => {
                const match =
                  line.match(/^\+\s+(\/.*\/[a-z]*)$/) ??
                  line.match(/^\+\s+if \((\/.*\/[a-z]*)\.test\(/);
                return match ? [match[1]] : [];
              });
            const regexFromLiteral = (literal) => {
              const closingSlash = literal.lastIndexOf("/");
              return new RegExp(
                literal.slice(1, closingSlash),
                literal.slice(closingSlash + 1)
              );
            };
            const regexes = regexLiterals.map(regexFromLiteral);
            const pick = (label, needle) => {
              const found = regexes.filter((regex) => regex.source.includes(needle));
              if (found.length !== 1) {
                throw new Error(
                  "shell-wrapper.patch must expose exactly one " +
                    label +
                    " regex, found " +
                    found.length
                );
              }
              return found[0];
            };
            const shebangPattern = pick("shebang", "bash|dash");
            const targetPattern = pick("target", "target=");
            const execPattern = pick("exec", "exec");
            for (const [name, path] of Object.entries(wrapperPaths)) {
              const wrapper = readFileSync(path, "utf8");
              if (!shebangPattern.test(wrapper.split("\n")[0])) {
                throw new Error(
                  "claude-code " +
                    name +
                    " wrapper shebang is not classified as a shell launcher"
                );
              }
              const matches = wrapper.split("\n").flatMap((line) => {
                const match = line.match(targetPattern);
                return match ? [match[1] ?? match[2] ?? match[3]] : [];
              });
              if (matches.length !== 1) {
                throw new Error(
                  "claude-code " +
                    name +
                    " wrapper must have exactly one target assignment, found " +
                    matches.length
                );
              }
              if (!matches[0].startsWith("/")) {
                throw new Error(
                  "claude-code " + name + " wrapper target is not absolute: " + matches[0]
                );
              }
            }
            const probe = readFileSync(process.env.PROBE_FILE, "utf8");
            if (!shebangPattern.test(probe.split("\n")[0])) {
              throw new Error(
                  "makeWrapper no longer emits a shebang classified as a shell launcher"
              );
            }
            const execMatch = probe.match(execPattern);
            if (!execMatch) {
              throw new Error(
                "makeWrapper no longer emits the exec form consumed by shell-wrapper.patch"
              );
            }
            if (execMatch[2] !== process.env.PROBE_WRAPPED) {
              throw new Error(
                "makeWrapper exec target capture is " +
                  execMatch[2] +
                  ", expected " +
                  process.env.PROBE_WRAPPED
              );
            }
            const innerProbe = readFileSync(process.env.PROBE_INNER, "utf8");
            if (!shebangPattern.test(innerProbe.split("\n")[0])) {
              throw new Error(
                "makeWrapper --inherit-argv0 no longer emits a shell-classified wrapper"
              );
            }
            const innerMatch = innerProbe.match(execPattern);
            if (!innerMatch || innerMatch[2] !== process.env.PROBE_TARGET) {
              throw new Error(
                "makeWrapper --inherit-argv0 exec form is not consumed by shell-wrapper.patch"
              );
            }
            const noArgProbe = readFileSync(process.env.PROBE_NO_ARG, "utf8");
            const noArgMatch = noArgProbe.match(execPattern);
            if (!noArgMatch || noArgMatch[2] !== process.env.PROBE_TARGET) {
              throw new Error(
                "makeShellWrapper no-argv0 exec form is not consumed by shell-wrapper.patch"
              );
            }
            if (/\bexec\s+-a\b/.test(noArgProbe)) {
              throw new Error("makeShellWrapper no-argv0 probe unexpectedly sets argv0");
            }
            const interpreterProbe = readFileSync(process.env.PROBE_INTERPRETER, "utf8");
            if (execPattern.test(interpreterProbe)) {
              throw new Error(
                "exec grammar resolves a generic makeWrapper interpreter wrapper"
              );
            }
            NODE
            echo "ok: Claude wrapper and shell-wrapper.patch contracts" > $out
          '';
    };

  flake.homeManagerModules.apps."claude-code" =
    {
      config,
      osConfig,
      lib,
      pkgs,
      agents,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "claude-code" "extended" "enable" ] false osConfig;
      claudePkg = lib.attrByPath [
        "programs"
        "claude-code"
        "extended"
        "package"
      ] pkgs.claude-code osConfig;
      installMethods = lib.attrByPath [ "programs" "claude-code" "extended" "installMethods" ] {
        nix.enable = false;
        bun.enable = false;
      } osConfig;

      defaults = import ./_default-settings.nix;
      claudeEnv = import ./_env.nix;
      plugins = import ./_plugins.nix { inherit lib osConfig; };
      inherit (plugins) greptilePluginRequested;

      # MCP servers via compiled agents.mcp client profile
      mcpServers = agents.mcp.clients.claude.servers pkgs;

      # Display names blocked via settings.json deniedMcpServers, mainly the
      # claude.ai account connectors that local config cannot otherwise remove.
      deniedMcpServers =
        lib.attrByPath
          [
            "programs"
            "claude-code"
            "extended"
            "deniedMcpServers"
          ]
          [ ]
          osConfig;

      settings = import ./_settings.nix {
        inherit
          pkgs
          defaults
          mcpServers
          deniedMcpServers
          ;
        inherit (plugins) enabledPlugins;
      };

      greptileApiKeyPath = "${config.xdg.dataHome}/greptile/api-key";
      greptileHeadersHelperPath = "${config.home.homeDirectory}/.local/bin/claude-greptile-mcp-headers";
      bunInstallDir = "${config.xdg.dataHome}/bun";
      configuredExternalBinary = lib.attrByPath [
        "programs"
        "claude-code"
        "extended"
        "externalBinary"
      ] null osConfig;
      externalBinary =
        if configuredExternalBinary == null then
          "${bunInstallDir}/bin/claude"
        else
          configuredExternalBinary;

      activation = import ./_activation.nix {
        inherit
          lib
          pkgs
          osConfig
          config
          greptileApiKeyPath
          greptileHeadersHelperPath
          ;
        inherit (settings) claudeSettingsFile claudeJsonConfigFile;
        inherit (plugins) greptilePluginKey greptilePluginRequested;
      };

      claudeRuntime = import ./_wrapper.nix {
        inherit
          lib
          pkgs
          claudePkg
          bunInstallDir
          externalBinary
          installMethods
          greptilePluginRequested
          greptileApiKeyPath
          ;
      };

      claudeInstructions = agents.systemPrompt.render {
        vars.questionTool = "AskUserQuestion";
      };

      # Install every compiled skill that ships a Claude profile at
      # ~/.claude/skills/<name>/SKILL.md, keyed off the shared registry so new
      # skills need no per-client wiring here.
      claudeSkillFiles = lib.mapAttrs' (
        name: skill: lib.nameValuePair ".claude/skills/${name}/SKILL.md" { text = skill.claude; }
      ) (lib.filterAttrs (_name: skill: skill ? claude) agents.skills.list);
    in
    {
      config = lib.mkIf nixosEnabled {
        home = {
          file = {
            ".claude/CLAUDE.md".text = claudeInstructions;

            ".claude/keybindings.json".text = builtins.toJSON defaults.claudeKeybindingsBase;

            ".local/bin/claude" = {
              source = lib.getExe claudeRuntime.claudeWrapped;
              executable = true;
            };
          }
          // claudeSkillFiles
          // lib.optionalAttrs greptilePluginRequested {
            ".local/bin/claude-greptile-mcp-headers" = {
              executable = true;
              text = ''
                #!${pkgs.bash}/bin/bash
                set -euo pipefail

                secret_path="''${GREPTILE_API_KEY_FILE:-${greptileApiKeyPath}}"
                if [ ! -r "$secret_path" ] || [ ! -s "$secret_path" ]; then
                  echo "GREPTILE_API_KEY file is not readable: $secret_path" >&2
                  exit 1
                fi

                secret_value="$(${pkgs.coreutils}/bin/tr -d '\r\n' < "$secret_path")"
                if [ -z "$secret_value" ]; then
                  echo "GREPTILE_API_KEY file is empty after normalization: $secret_path" >&2
                  exit 1
                fi

                ${pkgs.jq}/bin/jq -n --arg authorization "Bearer $secret_value" '{
                  Authorization: $authorization
                }'
              '';
            };
          };

          inherit activation;

          # bun puts its global bin on home.sessionPath; mkBefore orders
          # ~/.local/bin ahead of it so the wrapper shadows a bun-global claude.
          sessionPath = lib.mkBefore [ "${config.home.homeDirectory}/.local/bin" ];

          # Full env from the shared source (modules/agents/claude-code/_env.nix);
          # belt-and-suspenders with the binary postFixup and settings.json `env`.
          sessionVariables = claudeEnv.all;
        };
      };
    };
}

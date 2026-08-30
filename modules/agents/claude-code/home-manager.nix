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
        { installMethods }:
        import ./_wrapper.nix {
          inherit
            lib
            pkgs
            installMethods
            ;
          claudePkg = "/nix/store/test-claude";
          bunInstallDir = "/nix/store/test-bun";
          externalBinary = "/nix/store/test-external/bin/claude";
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
      variants = lib.mapAttrs (
        _name: installMethods: renderWrapper { inherit installMethods; }
      ) installMethodVariants;
      wrapperPaths = lib.mapAttrs (_: wrapper: lib.getExe wrapper.claudeWrapped) variants;
      # Hand translations of the two consumer regexes, the only pieces of the
      # contract evaluated outside the build script below.
      targetLinePattern = ''^[[:space:]]*target=('/[^']+'|"/[^"]+"|/[^[:space:]#]+)[[:space:]]*$'';
      shebangLinePattern = ".*[/[:space:]](bash|dash|zsh|ksh|ash|sh)([[:space:]].*)?";
      # writeShellScriptBin prepends "#!${pkgs.runtimeShell}", so the shebang
      # the classifier sees is never part of wrapperBody.
      wrapperShebangLine = "#!${pkgs.runtimeShell}";
      # Every regex the build script recovers from shell-wrapper.patch. CI
      # forces each check's drvPath but never builds one
      # (.github/workflows/check.yml), so the script is unreachable in CI;
      # pinning each literal here makes a patch-side edit fail eval instead of
      # silently drifting from targetLinePattern and the unexercised script.
      patchRegexLiterals = {
        shebang = ''/(?:^|[/\s])(?:bash|dash|zsh|ksh|ash|sh)(?:\s|$)/'';
        target = ''/^\s*target=(?:"([^"]+)"|'([^']+)'|([^\s#]+))\s*$/m'';
        exec = ''/^\s*exec\s+(?:-a\s+(?:"[^"]*"|'[^']*'|\S+)\s+)?(["'])(\/[^"'\n]*\/\.[^"'\n/]+-wrapped_*)\1/m'';
      };
      shellWrapperPatchText = builtins.readFile ../../../packages/tweakcc/shell-wrapper.patch;
      driftedPatchRegexes = lib.attrNames (
        lib.filterAttrs (_name: literal: !(lib.hasInfix literal shellWrapperPatchText)) patchRegexLiterals
      );
      wrapperTargetCounts = lib.mapAttrs (
        _name: wrapper:
        lib.count (line: builtins.match targetLinePattern line != null) (
          lib.splitString "\n" wrapper.wrapperBody
        )
      ) variants;
    in
    {
      checks."claude-code/wrapper-target-contract" =
        assert lib.assertMsg (driftedPatchRegexes == [ ])
          "packages/tweakcc/shell-wrapper.patch changed its ${lib.concatStringsSep ", " driftedPatchRegexes} regex; re-run the claude-code/wrapper-target-contract build and update modules/agents/claude-code/home-manager.nix";
        assert lib.assertMsg (builtins.match shebangLinePattern wrapperShebangLine != null)
          "claude-code wrapper shebang ${wrapperShebangLine} is not classified as a shell launcher by packages/tweakcc/shell-wrapper.patch, so the target= resolver is never reached";
        assert lib.assertMsg (lib.all (count: count == 1) (lib.attrValues wrapperTargetCounts))
          "claude-code wrapper lost its single standalone absolute target assignment consumed by packages/tweakcc/shell-wrapper.patch";
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
          claudeEnv
          ;
        claudeDefaults = defaults;
        inherit (settings) claudeSettingsFile claudeJsonConfigFile;
      };

      claudeRuntime = import ./_wrapper.nix {
        inherit
          lib
          pkgs
          claudePkg
          bunInstallDir
          externalBinary
          installMethods
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

            # Same launcher with the telemetry opt-out lifted, which is what
            # `claude rc` needs; see launchOnly in _env.nix.
            ".local/bin/claude-rc" = {
              source = lib.getExe claudeRuntime.claudeRcWrapped;
              executable = true;
            };
          }
          // claudeSkillFiles;

          inherit activation;

          # bun puts its global bin on home.sessionPath; mkBefore orders
          # ~/.local/bin ahead of it so the wrapper shadows a bun-global claude.
          sessionPath = lib.mkBefore [ "${config.home.homeDirectory}/.local/bin" ];

          # Full env from the shared source (modules/agents/claude-code/_env.nix);
          # belt-and-suspenders with the binary postFixup and settings.json `env`.
          # launchOnly is safe to add here, unlike in `settings` or `binary`,
          # because claude-rc unsets it before exec and so still starts clean;
          # this keeps the opt-out on a bun binary invoked outside the wrapper.
          sessionVariables = claudeEnv.all // claudeEnv.launchOnly;
        };
      };
    };
}

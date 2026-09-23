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
    * Per-skill availability for standalone Claude Code skills is governed by
      programs.claude-code.extended.skillOverrides in modules/apps/claude-code.nix.
    * `enabledPlugins` keys end with `@<marketplace>`. The marketplace must be
      registered first: declaratively via _default-settings.nix's
      claudeSettingsBase.extraKnownMarketplaces (as chrome-devtools-plugins
      and cloudflare are), or out of band in
      ~/.claude/plugins/known_marketplaces.json (as claude-plugins-official
      is, installed once with
      `claude-plugins install anthropics/claude-plugins-official`). `builtin`
      needs no registration; entries naming an unregistered marketplace are
      silently ignored.
    * Config is split across private helpers in modules/agents/claude-code/:
        _default-settings.nix  static defaults for settings.json, .claude.json,
                               and keybindings.json
        _plugins.nix           enabledPlugins composition from osConfig
        _settings.nix          merges defaults + plugins + skillOverrides + mcpServers
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
      # Every regex the build script recovers from shell-wrapper.patch. The
      # check below opts into CI's runtime build (passthru.runtimeCheck), so
      # the script does run there, but only on `nix build`; pinning each
      # literal here additionally fails eval, catching a patch-side drift in
      # `nix flake check --no-build` without waiting on a full build.
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
      checks = {
        "claude-code/wrapper-target-contract" =
          assert lib.assertMsg (driftedPatchRegexes == [ ])
            "packages/tweakcc/shell-wrapper.patch changed its ${lib.concatStringsSep ", " driftedPatchRegexes} regex; re-run the claude-code/wrapper-target-contract build and update modules/agents/claude-code/home-manager.nix";
          assert lib.assertMsg (builtins.match shebangLinePattern wrapperShebangLine != null)
            "claude-code wrapper shebang ${wrapperShebangLine} is not classified as a shell launcher by packages/tweakcc/shell-wrapper.patch, so the target= resolver is never reached";
          assert lib.assertMsg (lib.all (count: count == 1) (lib.attrValues wrapperTargetCounts))
            "claude-code wrapper lost its single standalone absolute target assignment consumed by packages/tweakcc/shell-wrapper.patch";
          pkgs.runCommandLocal "claude-code-wrapper-target-contract"
            {
              passthru.runtimeCheck = true;
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

        # Regression coverage for _activation.nix's settingsMergeJq: a prior
        # round of this same jq program shipped a byte-for-byte no-op fix that
        # passed `nix flake check` and needed a human read to catch (16e377d9,
        # reverted in f17e65de). This exercises the real production filter
        # (not a hand-copied approximation) against a fixture covering the two
        # merge policies _activation.nix's header documents an explicit rule
        # for (skillOverrides full ownership, extraKnownMarketplaces per-entry
        # wholesale replace), plus deniedMcpServers' union-and-dedupe (in the
        # real [{serverName = "…";}] shape _settings.nix renders, with an
        # overlapping entry so `| unique` is actually exercised) and the
        # retired/legacy env var deletions (using the only arm production can
        # reach: $nix never sets a legacy-named key, so the fixture tests the
        # deletion firing, not a same-key override surviving). enabledPlugins'
        # and env's unions are asserted too, even though both come from the
        # ambient `*` merge rather than an explicit rule (a second explicit
        # rule for either was dead code, removed here and in bfb8d432):
        # enabledPlugins alone has now shipped a no-op fix twice for two
        # different reasons (16e377d9's, and the redundant rule bfb8d432
        # removed), so both observable contracts keep a regression check
        # independent of which mechanism currently provides them. Both fixtures
        # also stage one key each ("kept@mkt", CONTESTED) present on both sides
        # with conflicting values, asserted to resolve to $nix's: this pins the
        # merge's precedence direction, not just its union of keys, which is
        # what lets a declared change actually take effect on a machine that
        # already switched (this PR's own extraPlugins default flips depend on
        # it). This check opts into
        # .github/workflows/check.yml's "Run runtime check suites" step via
        # passthru.runtimeCheck below; without that, its assertions evaluate
        # here but CI never builds this derivation, so none of them run there.
        "claude-code/settings-merge" =
          let
            activationFixture = import ./_activation.nix {
              inherit lib pkgs;
              osConfig = { };
              config.xdg.dataHome = "/var/empty";
              claudeEnv = import ./_env.nix;
              claudeDefaults = import ./_default-settings.nix;
              managedClaudeSkillNames = [ "commit" ];
              claudeSettingsFile = pkgs.writeText "settings-merge-fixture-nix-unused.json" "{}";
              claudeJsonConfigFile = pkgs.writeText "settings-merge-fixture-json-unused.json" "{}";
            };
            existingFixture = {
              enabledPlugins = {
                "gone@mkt" = true;
                # $nix sets this key too, to a different value: pins $nix
                # winning the conflict, not just the union of keys.
                "kept@mkt" = false;
              };
              extraKnownMarketplaces.cloudflare.source = {
                source = "git";
                url = "https://github.com/cloudflare/skills.git";
                sparsePaths = [ ".claude-plugin" ];
              };
              skillOverrides = {
                commit = "off";
                "some-plugin-skill" = "off";
              };
              # _settings.nix renders deniedMcpServers as [{ serverName = "…"; }],
              # not bare strings; "claude.ai Todoist" overlaps with nixFixture's
              # entry below to exercise `| unique`, since two disjoint one-entry
              # arrays would union to the same length with or without it.
              deniedMcpServers = [
                { serverName = "claude.ai Kept By User"; }
                { serverName = "claude.ai Todoist"; }
              ];
              env = {
                # In claudeEnv.stripped (_env.nix): unconditionally deleted.
                CLAUDE_CODE_ENABLE_TELEMETRY = "1";
                # In claudeEnv.legacyEnvValues (_env.nix): deleted only if the
                # merged value still equals this legacy value. $nix never sets
                # this key (claudeEnv.settings does not carry it), so this is
                # the only arm production can reach; nixFixture deliberately
                # does not override it.
                CLAUDE_CODE_DISABLE_TERMINAL_TITLE = "0";
                USER_KEPT = "keep";
                # $nix sets this key too, to a different value: pins $nix
                # winning the conflict, not just the union of keys.
                CONTESTED = "existing";
              };
            };
            nixFixture = {
              enabledPlugins."kept@mkt" = true;
              extraKnownMarketplaces.cloudflare.source = {
                source = "git";
                url = "https://github.com/cloudflare/skills.git";
              };
              skillOverrides = { };
              deniedMcpServers = [
                { serverName = "claude.ai Todoist"; }
                { serverName = "claude.ai Cloudflare Developer Platform"; }
              ];
              env.CONTESTED = "nix";
            };
          in
          pkgs.runCommandLocal "claude-code-settings-merge"
            {
              # .github/workflows/check.yml's "Check flake" step only forces
              # drvPaths; a check's assertions only run in CI if its name
              # matches script-tests-.* or it opts in here (see that workflow's
              # "Run runtime check suites" step and modules/meta/script-tests.nix).
              passthru.runtimeCheck = true;
              existingJson = builtins.toJSON existingFixture;
              nixJson = builtins.toJSON nixFixture;
              passAsFile = [
                "existingJson"
                "nixJson"
              ];
              mergeFilter = activationFixture.settingsMergeJq;
            }
            ''
              merged=$(${lib.getExe pkgs.jq} \
                ${lib.escapeShellArgs activationFixture.settingsMergeJqArgs} \
                --slurpfile nixSettings "$nixJsonPath" \
                "$mergeFilter" \
                "$existingJsonPath")

              check() {
                local desc="$1" query="$2" expected="$3"
                local actual
                actual=$(echo "$merged" | ${lib.getExe pkgs.jq} -c "$query")
                if [ "$actual" != "$expected" ]; then
                  echo "FAIL: $desc: query $query expected $expected, got $actual" >&2
                  echo "$merged" >&2
                  exit 1
                fi
              }

              # skillOverrides: a managed name absent from $nix is cleared, not carried over.
              check "managed skillOverrides name cleared" '.skillOverrides | has("commit")' "false"
              # skillOverrides: an unmanaged name is preserved though $nix never touches it.
              check "unmanaged skillOverrides name preserved" '.skillOverrides."some-plugin-skill"' '"off"'
              # extraKnownMarketplaces: per-entry wholesale replace drops a subkey $nix omits.
              check "extraKnownMarketplaces entry replaced wholesale" \
                '.extraKnownMarketplaces.cloudflare.source | has("sparsePaths")' "false"
              # enabledPlugins: the ambient `*` merge preserves a key $nix no longer declares.
              check "enabledPlugins stale key preserved by union" '.enabledPlugins."gone@mkt"' "true"
              # enabledPlugins: $nix's value wins a same-key conflict; this is what
              # lets extraPlugins actually flip a previously-true default to false
              # on a machine that already switched.
              check "enabledPlugins nix value wins" '.enabledPlugins."kept@mkt"' "true"
              # deniedMcpServers: explicit union-and-dedupe, not `*`'s whole-array replace.
              # Without `| unique` this is 4, since "claude.ai Todoist" appears on both sides.
              check "deniedMcpServers unions and dedupes both sides" '.deniedMcpServers | length' "3"
              check "deniedMcpServers keeps the user-only entry" \
                '[.deniedMcpServers[].serverName] | index("claude.ai Kept By User") != null' "true"
              # retired env names (claudeEnv.stripped) are deleted unconditionally.
              check "retired env name deleted" '.env | has("CLAUDE_CODE_ENABLE_TELEMETRY")' "false"
              # env keys neither side's rules touch are preserved.
              check "user env preserved" '.env.USER_KEPT' '"keep"'
              # env: $nix's value wins a same-key conflict, same property as enabledPlugins above.
              check "env nix value wins" '.env.CONTESTED' '"nix"'
              # legacy env values are deleted when the merged value still equals
              # the legacy value $nix never sets (see existingFixture's comment).
              check "legacy env value deleted" '.env | has("CLAUDE_CODE_DISABLE_TERMINAL_TITLE")' "false"

              echo "ok: claude-code settings-merge jq contract" > $out
            '';

        # Regression coverage for _activation.nix's claudeJsonMergeJq, the
        # ~/.claude.json sibling of settingsMergeJq above and covering the
        # same risk: mcpServers' per-entry wholesale replace (dropping a stale
        # command/args pair a changed transport type leaves behind, the same
        # shape as extraKnownMarketplaces) and retiredJsonJq (live:
        # claudeDefaults.retired.claudeJson is non-empty).
        "claude-code/claude-json-merge" =
          let
            activationFixture = import ./_activation.nix {
              inherit lib pkgs;
              osConfig = { };
              config.xdg.dataHome = "/var/empty";
              claudeEnv = import ./_env.nix;
              claudeDefaults = import ./_default-settings.nix;
              managedClaudeSkillNames = [ ];
              claudeSettingsFile = pkgs.writeText "claude-json-merge-fixture-settings-unused.json" "{}";
              claudeJsonConfigFile = pkgs.writeText "claude-json-merge-fixture-unused.json" "{}";
            };
            existingFixture = {
              mcpServers = {
                # Stale transport fields a changed server type leaves behind;
                # $nix's entry below omits them entirely.
                ctx7 = {
                  command = "old-command";
                  args = [ "old-arg" ];
                };
                "existing-only" = {
                  command = "keep-me";
                };
              };
              # In claudeDefaults.retired.claudeJson (_default-settings.nix): deleted unconditionally.
              autocheckpointingEnabled = true;
            };
            nixFixture = {
              mcpServers.ctx7 = {
                type = "http";
                url = "https://example.invalid/mcp";
              };
            };
          in
          pkgs.runCommandLocal "claude-code-claude-json-merge"
            {
              passthru.runtimeCheck = true;
              existingJson = builtins.toJSON existingFixture;
              nixJson = builtins.toJSON nixFixture;
              passAsFile = [
                "existingJson"
                "nixJson"
              ];
              mergeFilter = activationFixture.claudeJsonMergeJq;
            }
            ''
              merged=$(${lib.getExe pkgs.jq} \
                --slurpfile nixConfig "$nixJsonPath" \
                "$mergeFilter" \
                "$existingJsonPath")

              check() {
                local desc="$1" query="$2" expected="$3"
                local actual
                actual=$(echo "$merged" | ${lib.getExe pkgs.jq} -c "$query")
                if [ "$actual" != "$expected" ]; then
                  echo "FAIL: $desc: query $query expected $expected, got $actual" >&2
                  echo "$merged" >&2
                  exit 1
                fi
              }

              # mcpServers: per-entry wholesale replace drops stale fields $nix omits.
              check "mcpServers entry replaced wholesale" '.mcpServers.ctx7 | has("command")' "false"
              check "mcpServers nix value present" '.mcpServers.ctx7.type' '"http"'
              # mcpServers: an existing-only entry survives the per-entry union.
              check "mcpServers existing-only entry preserved" '.mcpServers."existing-only".command' '"keep-me"'
              # retired claudeJson keys (claudeDefaults.retired.claudeJson) are deleted unconditionally.
              check "retired claudeJson key deleted" 'has("autocheckpointingEnabled")' "false"

              echo "ok: claude-code claude-json-merge jq contract" > $out
            '';
      };
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
      registryClaudeSkills = lib.filterAttrs (_name: skill: skill ? claude) agents.skills.list;
      managedClaudeSkillNames = lib.attrNames registryClaudeSkills;
      configuredSkillOverrides = lib.attrByPath [
        "programs"
        "claude-code"
        "extended"
        "skillOverrides"
      ] { } osConfig;
      unknownSkillOverrides = lib.attrNames (
        builtins.removeAttrs configuredSkillOverrides managedClaudeSkillNames
      );
      skillOverrides = configuredSkillOverrides;

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
          lib
          pkgs
          defaults
          mcpServers
          deniedMcpServers
          skillOverrides
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

      # settingsMergeJq, settingsMergeJqArgs, and claudeJsonMergeJq are all
      # unused here; checks."claude-code/settings-merge" and
      # checks."claude-code/claude-json-merge" above import _activation.nix
      # separately to exercise them against fixtures.
      activationResult = import ./_activation.nix {
        inherit
          lib
          pkgs
          osConfig
          config
          claudeEnv
          managedClaudeSkillNames
          ;
        claudeDefaults = defaults;
        inherit (settings) claudeSettingsFile claudeJsonConfigFile;
      };
      inherit (activationResult) activation;

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
      ) registryClaudeSkills;
    in
    {
      config = lib.mkIf nixosEnabled {
        assertions = [
          {
            assertion = unknownSkillOverrides == [ ];
            message = "programs.claude-code.extended.skillOverrides has unknown skill names: ${lib.concatStringsSep ", " unknownSkillOverrides}. Managed Claude Code skills: ${lib.concatStringsSep ", " managedClaudeSkillNames}.";
          }
        ];

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

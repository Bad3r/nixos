{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      renderWrapper =
        { installMethods }:
        import ./_launcher.nix {
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
            "packages/tweakcc/shell-wrapper.patch changed its ${lib.concatStringsSep ", " driftedPatchRegexes} regex; re-run the claude-code/wrapper-target-contract build and update modules/agents/claude-code/checks.nix";
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

        # Runs the real claude-code-apply-config against a fake HOME. This opts
        # into .github/workflows/check.yml's "Run runtime check suites" step via
        # passthru.runtimeCheck; without it CI only forces the drvPath.
        "claude-code/activation-merge" =
          let
            inherit
              (import ./_activation.nix {
                inherit lib pkgs;
                osConfig = { };
                config.xdg.dataHome = "/var/empty";
                claudeSettingsFile = null;
                claudeJsonConfigFile = null;
                stateFile = null;
              })
              applyConfig
              ;
            json = name: value: pkgs.writeText name (builtins.toJSON value);
            settingsTemplate = json "settings-template.json" {
              enabledPlugins."kept@mkt" = true;
              model = "nix-model";
              permissions.allow = [ "Read(**)" ];
            };
            claudeJsonTemplate = json "claude-json-template.json" {
              mcpServers.ctx7 = {
                type = "http";
                url = "https://example.invalid/mcp";
              };
              theme = "dark";
            };
            stateTemplate = json "state-template.json" {
              version = 1;
              settings = [
                "enabledPlugins"
                "model"
                "permissions"
              ];
              claudeJson = [ "theme" ];
              mcpServers = [ "ctx7" ];
            };
            liveSettings = json "live-settings.json" {
              enabledPlugins = {
                "gone@mkt" = true;
                "kept@mkt" = false;
              };
              model = "user-model";
              permissions = {
                additionalDirectories = [ "/tmp" ];
                allow = [ "Bash(ls *)" ];
              };
              # Recorded by the previous switch, no longer declared.
              staleKey = true;
              # Written by Claude, never recorded.
              tui = "fullscreen";
            };
            liveClaudeJson = json "live-claude-json.json" {
              mcpServers = {
                ctx7 = {
                  command = "old";
                  args = [ "old" ];
                };
                mine.command = "keep-me";
                oldNix.command = "gone";
              };
              numStartups = 7;
              staleUi = "x";
              theme = "light";
            };
            previousState = json "previous-state.json" {
              version = 1;
              settings = [
                "enabledPlugins"
                "model"
                "permissions"
                "staleKey"
              ];
              claudeJson = [
                "staleUi"
                "theme"
              ];
              mcpServers = [
                "ctx7"
                "oldNix"
              ];
            };
          in
          pkgs.runCommandLocal "claude-code-activation-merge"
            {
              passthru.runtimeCheck = true;
              nativeBuildInputs = [ pkgs.jq ];
            }
            ''
              apply() {
                ${lib.getExe applyConfig} ${settingsTemplate} ${claudeJsonTemplate} ${stateTemplate}
              }
              check() {
                local file=$1 query=$2 expected=$3 actual
                actual=$(jq -cS "$query" "$file")
                if [ "$actual" != "$expected" ]; then
                  echo "FAIL: $file: $query: expected $expected, got $actual" >&2
                  exit 1
                fi
              }
              seed() {
                export HOME=$PWD/$1
                mkdir -p "$HOME/.claude"
              }
              put() {
                install -m 600 "$1" "$2"
              }

              # A record from the previous switch.
              seed recorded
              put ${liveSettings} "$HOME/.claude/settings.json"
              put ${liveClaudeJson} "$HOME/.claude.json"
              put ${previousState} "$HOME/.claude/.nix-managed.json"
              apply
              s=$HOME/.claude/settings.json
              c=$HOME/.claude.json
              check "$s" 'has("staleKey")' false
              check "$s" '.tui' '"fullscreen"'
              check "$s" '.model' '"nix-model"'
              check "$s" '.enabledPlugins' '{"kept@mkt":true}'
              check "$s" '.permissions' '{"allow":["Read(**)"]}'
              check "$c" 'has("staleUi")' false
              check "$c" '.numStartups' 7
              check "$c" '.theme' '"dark"'
              check "$c" '.mcpServers.ctx7' '{"type":"http","url":"https://example.invalid/mcp"}'
              check "$c" '.mcpServers | has("oldNix")' false
              check "$c" '.mcpServers.mine' '{"command":"keep-me"}'
              cmp ${stateTemplate} "$HOME/.claude/.nix-managed.json"

              # A second run changes nothing.
              cp "$s" settings.first
              cp "$c" claude-json.first
              apply
              cmp settings.first "$s"
              cmp claude-json.first "$c"

              # Without a record nothing is deleted, and the record is seeded.
              seed first-run
              put ${liveSettings} "$HOME/.claude/settings.json"
              put ${liveClaudeJson} "$HOME/.claude.json"
              apply
              check "$HOME/.claude/settings.json" 'has("staleKey")' true
              check "$HOME/.claude/settings.json" '.model' '"nix-model"'
              check "$HOME/.claude.json" '.mcpServers | has("oldNix")' true
              cmp ${stateTemplate} "$HOME/.claude/.nix-managed.json"

              # An empty settings.json and a missing ~/.claude.json read as {}.
              seed empty
              : >"$HOME/.claude/settings.json"
              apply
              check "$HOME/.claude/settings.json" '.model' '"nix-model"'
              check "$HOME/.claude.json" '.mcpServers.ctx7.type' '"http"'

              # A record that is not version 1 aborts before any file changes.
              n=0
              for record in 'not json' "" '{"version":2,"settings":[],"claudeJson":[],"mcpServers":[]}'; do
                n=$((n + 1))
                seed "corrupt-$n"
                put ${liveSettings} "$HOME/.claude/settings.json"
                printf '%s' "$record" >"$HOME/.claude/.nix-managed.json"
                if apply; then
                  echo "FAIL: record accepted: $record" >&2
                  exit 1
                fi
                cmp ${liveSettings} "$HOME/.claude/settings.json"
                [ ! -e "$HOME/.claude.json" ]
              done

              # A live file that is not one JSON object aborts and stays as is.
              seed not-object
              printf '[]' >"$HOME/.claude/settings.json"
              if apply; then
                echo "FAIL: array settings.json accepted" >&2
                exit 1
              fi
              [ "$(cat "$HOME/.claude/settings.json")" = "[]" ]

              echo "ok: claude-code-apply-config contract" >$out
            '';
      };
    };
}

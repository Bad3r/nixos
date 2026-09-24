/*
  Home Manager activation for Claude Code.

  claude-code-apply-config merges the Nix templates into ~/.claude/settings.json
  and ~/.claude.json, files Claude Code also writes itself. Every top-level key
  a template declares is written exactly as declared, a key the previous switch
  wrote and the template no longer declares is deleted (the record lives in
  ~/.claude/.nix-managed.json), and keys only Claude wrote are left alone.
  ~/.claude.json's mcpServers applies the same rule per server.

  The bun bindings stay lazy: with the bun install method off,
  osConfig.programs.bun is never read, so hosts without that option evaluate.
*/
{
  lib,
  pkgs,
  osConfig,
  config,
  claudeSettingsFile,
  claudeJsonConfigFile,
  stateFile,
}:
let
  applyConfig = pkgs.writeShellApplication {
    name = "claude-code-apply-config";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    # The single-quoted $names in the jq filters are jq variables.
    excludeShellChecks = [ "SC2016" ];
    text = ''
      settings_template=$1
      claude_json_template=$2
      state_template=$3

      settings="$HOME/.claude/settings.json"
      claude_json="$HOME/.claude.json"
      state="$HOME/.claude/.nix-managed.json"

      tmp_files=()
      cleanup() {
        if [ "''${#tmp_files[@]}" -gt 0 ]; then
          rm -f -- "''${tmp_files[@]}"
        fi
      }
      trap cleanup EXIT

      mkdir -p "$HOME/.claude"

      # The keys the previous switch wrote. Without a record nothing is deleted, so
      # the first run only adds and overwrites.
      if [ -e "$state" ]; then
        if ! jq -e --slurp '
            length == 1
            and (.[0] | type == "object" and .version == 1
              and ([.settings, .claudeJson, .mcpServers]
                | all(type == "array" and all(.[]; type == "string"))))
          ' "$state" >/dev/null 2>&1; then
          echo "claude-code-apply-config: $state is not a version 1 record; fix it, or delete it to reseed" >&2
          exit 1
        fi
        previous=$state
      else
        previous=$(mktemp)
        tmp_files+=("$previous")
        printf '%s\n' '{"version":1,"settings":[],"claudeJson":[],"mcpServers":[]}' >"$previous"
      fi

      # merge TARGET TEMPLATE FILTER: a missing or empty TARGET reads as {}; anything
      # but one JSON object aborts before TARGET is replaced.
      merge() {
        local target=$1 template=$2 filter=$3 tmp
        tmp=$(mktemp "$target.nix-XXXXXX")
        tmp_files+=("$tmp")
        if ! {
          if [ -s "$target" ]; then cat -- "$target"; else printf '{}\n'; fi
        } | jq --slurp --arg target "$target" \
          --slurpfile nix "$template" --slurpfile state "$previous" '
            if length == 1 and (.[0] | type) == "object" then .[0]
            else error("\($target) is not a single JSON object") end
            | '"$filter" >"$tmp"; then
          echo "claude-code-apply-config: $target left unchanged" >&2
          exit 1
        fi
        mv -f -- "$tmp" "$target"
      }

      merge "$settings" "$settings_template" '
        $nix[0] as $declared
        | reduce (($state[0].settings) - ($declared | keys))[] as $key (.; del(.[$key]))
        | . + $declared
      '

      merge "$claude_json" "$claude_json_template" '
        ($nix[0] | del(.mcpServers)) as $declared
        | ($nix[0].mcpServers // {}) as $servers
        | reduce (($state[0].claudeJson) - ($declared | keys))[] as $key (.; del(.[$key]))
        | . + $declared
        | .mcpServers |= (
            (. // {})
            | if type == "object" then . else error("mcpServers is not an object") end
            | reduce (($state[0].mcpServers) - ($servers | keys))[] as $name (.; del(.[$name]))
            | . + $servers
          )
      '

      tmp=$(mktemp "$state.nix-XXXXXX")
      tmp_files+=("$tmp")
      cat -- "$state_template" >"$tmp"
      mv -f -- "$tmp" "$state"

      echo "Claude Code: settings.json and .claude.json updated"
    '';
  };

  bunInstallEnabled = lib.attrByPath [
    "programs"
    "claude-code"
    "extended"
    "installMethods"
    "bun"
    "enable"
  ] false osConfig;
  bunInstallDir = "${config.xdg.dataHome}/bun";
  bunBin = lib.getExe osConfig.programs.bun.extended.package;
in
{
  inherit applyConfig;
  activation = {
    claudeCodeSetup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe applyConfig} ${claudeSettingsFile} ${claudeJsonConfigFile} ${stateFile}
    '';
  }
  // lib.optionalAttrs bunInstallEnabled {
    # The probe URL is pinned to the public npm registry because every
    # host in this repo runs bun against the default registry. If a
    # future host points bun at a private mirror via `~/.bunfig.toml`
    # or `BUN_CONFIG_REGISTRY`, this probe will check the wrong
    # endpoint and either skip a working install or run an install
    # that fails immediately. Update the URL alongside the bun config
    # if that ever happens.
    installClaudeCodeViaBun = lib.hm.dag.entryAfter [ "writeBoundary" "createBunDir" ] ''
      export BUN_INSTALL="${bunInstallDir}"
      if ${pkgs.curl}/bin/curl --silent --show-error --fail --max-time 5 \
          --output /dev/null \
          https://registry.npmjs.org/@anthropic-ai/claude-code/latest; then
        run ${bunBin} install -g @anthropic-ai/claude-code
      elif [ -x "$BUN_INSTALL/bin/claude" ]; then
        echo "warning: installClaudeCodeViaBun: npm registry probe failed (see curl error above), keeping existing install at $BUN_INSTALL/bin/claude" >&2
      else
        echo "warning: installClaudeCodeViaBun: npm registry probe failed (see curl error above) and no existing claude-code binary at $BUN_INSTALL/bin/claude; rerun home-manager switch once the registry is reachable" >&2
      fi
    '';
  };
}

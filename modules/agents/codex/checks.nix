{
  config,
  lib,
  inputs,
  ...
}:
let
  agents = config.flake.lib.agents;
in
{
  perSystem =
    { pkgs, system, ... }:
    let
      codexPkg = inputs.llm-agents.packages.${system}.codex;
      settings = import ./_settings.nix {
        inherit agents lib pkgs;
        homeDir = "/home/codex-config-check";
      };
      execPolicy = import ./_exec-policy.nix { inherit lib pkgs; };
      runtime = import ./_wrapper.nix {
        inherit lib pkgs codexPkg;
        inherit (settings) baseSettings nixProjectSettings;
        inherit (execPolicy) codexBashWrapper;
        homeDir = "/home/codex-config-check";
        configDir = "/home/codex-config-check/.config/codex";
      };
      codexServers = settings.baseSettings.mcp_servers;
      claudeServers = agents.mcp.clients.claude.servers pkgs;
      sharedNames = lib.intersectLists (lib.attrNames codexServers) (lib.attrNames claudeServers);
      validCodexServer = server: !(server ? type) && !(server ? startup_timeout_ms);
      sharedServerMatches =
        name:
        codexServers.${name} == builtins.removeAttrs claudeServers.${name} [
          "type"
          "startup_timeout_ms"
        ];
    in
    {
      checks."codex/config" =
        assert lib.assertMsg (
          !(settings.baseSettings ? commit_attribution)
        ) "Codex removed commit_attribution; express commit policy in AGENTS.md";
        assert lib.assertMsg (lib.all validCodexServer (
          lib.attrValues codexServers
        )) "Codex MCP output must omit transport type and the duplicate millisecond timeout";
        assert lib.assertMsg (lib.all sharedServerMatches sharedNames)
          "Shared MCP server commands, URLs, arguments, and timeouts differ between clients";
        pkgs.runCommandLocal "codex-config-check"
          {
            nativeBuildInputs = [ pkgs.uv ];
            UV_PYTHON = lib.getExe pkgs.python314;
            UV_NO_MANAGED_PYTHON = "1";
            UV_OFFLINE = "1";
            UV_NO_CACHE = "1";
            passthru.runtimeCheck = true;
          }
          ''
            mkdir -p "$PWD/codex"
            ln -s ${runtime.baseConfigFile} "$PWD/codex/config.base.toml"
            ln -s ${runtime.nixProjectsFile} "$PWD/codex/projects.nix.toml"
            cat > "$PWD/codex/trusted-projects.toml" <<'TOML'
            [projects."/tmp/codex-user-project"]
            trust_level = "trusted"
            TOML

            env CODEX_HOME="$PWD/codex" \
              ${lib.getExe runtime.codexWrapped} --strict-config app-server --stdio < /dev/null

            uv run --no-project - "$PWD/codex" ${lib.getExe codexPkg} <<'PY'
            import os
            from pathlib import Path
            import subprocess
            import sys
            import tomllib

            directory = Path(sys.argv[1])
            executable = sys.argv[2]
            config_path = directory / "config.toml"
            original = config_path.read_text()
            config = tomllib.loads(original)
            assert config["projects"]["/tmp/codex-user-project"]["trust_level"] == "trusted"
            assert config["projects"]["/home/codex-config-check/nixos"]["trust_level"] == "trusted"
            environment = dict(os.environ, CODEX_HOME=str(directory))

            features = subprocess.run(
                [executable, "features", "list"], env=environment,
                capture_output=True, text=True, check=True, timeout=30,
            )
            for line in features.stdout.splitlines():
                name, *stage, enabled = line.split()
                if name in config["features"]:
                    assert " ".join(stage) not in {"removed", "deprecated"}, line

            cases = {
                "commit_attribution": 'commit_attribution = ""\n' + original,
                "mcp_servers.config-regression.type": original + '\n[mcp_servers.config-regression]\ncommand = "unused"\ntype = "stdio"\n',
            }
            for field, text in cases.items():
                config_path.write_text(text)
                result = subprocess.run(
                    [executable, "--strict-config", "app-server", "--stdio"],
                    env=environment, input="", capture_output=True, text=True, timeout=30,
                )
                assert result.returncode != 0, f"strict config accepted {field}"
                assert f"unknown configuration field `{field}`" in result.stderr, result.stderr
            config_path.write_text(original)
            PY
            touch "$out"
          '';
    };
}

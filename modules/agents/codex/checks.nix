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
      # Turns on the `app` servers' rows; a null osConfig drops them.
      osConfig.programs.sbx.extended = {
        enable = true;
        finalPackage = pkgs.emptyDirectory;
        limits.maxTtl = 1;
      };
      settings = import ./_settings.nix {
        inherit
          agents
          lib
          osConfig
          pkgs
          ;
        homeDir = "/home/codex-config-check";
      };
      execPolicy = import ./_exec-policy.nix {
        inherit lib pkgs;
        scratchDir = "/tmp/codex-config-check-scratch";
      };
      runtime = import ./_wrapper.nix {
        inherit lib pkgs codexPkg;
        scratchDir = "/tmp/codex-config-check-scratch";
        inherit (settings) baseSettings nixProjectSettings;
        inherit (execPolicy) codexBashWrapper;
        homeDir = "/home/codex-config-check";
        configDir = "/home/codex-config-check/.config/codex";
      };
      codexServers = settings.baseSettings.mcp_servers;
      claudeServers = agents.mcp.clients.claude.servers { inherit pkgs osConfig; };
      sharedNames = lib.intersectLists (lib.attrNames codexServers) (lib.attrNames claudeServers);
      validCodexServer = server: !(server ? type) && !(server ? startup_timeout_ms);
      sharedServerMatches =
        name:
        builtins.removeAttrs codexServers.${name} [ "default_tools_approval_mode" ]
        == builtins.removeAttrs claudeServers.${name} [
          "type"
          "startup_timeout_ms"
          "timeout"
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

            uv run --no-project - "$PWD/codex" ${lib.getExe codexPkg} ${lib.getExe runtime.codexWrapped} <<'PY'
            import os
            from pathlib import Path
            import subprocess
            import sys
            import tomllib

            directory = Path(sys.argv[1])
            executable = sys.argv[2]
            wrapper = sys.argv[3]
            config_path = directory / "config.toml"
            original = config_path.read_text()
            config = tomllib.loads(original)
            assert config["approval_policy"] == "on-request"
            assert config["approvals_reviewer"] == "auto_review"
            assert config["projects"]["/tmp/codex-user-project"]["trust_level"] == "trusted"
            assert config["projects"]["/home/codex-config-check/nixos"]["trust_level"] == "trusted"
            environment = dict(os.environ, CODEX_HOME=str(directory))

            def launch(*args):
                return subprocess.run(
                    [wrapper, "--strict-config", *args, "app-server", "--stdio"],
                    env=environment, input="", capture_output=True, text=True, timeout=30,
                )

            overrides = directory / "overrides.toml"
            overrides.write_text('approvals_reviewer = "user"\n')
            result = launch()
            assert result.returncode == 0, result.stderr
            assert tomllib.loads(config_path.read_text())["approvals_reviewer"] == "user"

            projects = directory / "trusted-projects.toml"
            projects.write_text(projects.read_text() + '\n[projects."/extra-project"]\ntrust_level = "trusted"\n')
            result = launch()
            assert result.returncode == 0, result.stderr
            assert tomllib.loads(config_path.read_text())["approvals_reviewer"] == "user"

            overrides.write_text('approvals_reviewer = [\n')
            previous_config = config_path.read_text()
            result = launch()
            assert result.returncode != 0, "invalid overrides were accepted"
            assert "user overrides: invalid TOML" in result.stderr, result.stderr
            assert config_path.read_text() == previous_config

            overrides.unlink()
            result = launch()
            assert result.returncode == 0, result.stderr
            assert tomllib.loads(config_path.read_text())["approvals_reviewer"] == "auto_review"

            result = launch('-c', 'approvals_reviewer="user"')
            assert result.returncode == 0, result.stderr

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

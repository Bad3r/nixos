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
      # Include app-backed MCP entries in parser validation without building their services.
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
      telemetry = import ./_telemetry.nix { inherit pkgs; };
    in
    {
      checks."codex/telemetry-collector" =
        pkgs.runCommandLocal "codex-telemetry-collector-check" { passthru.runtimeCheck = true; }
          ''
            STATE_DIRECTORY="$TMPDIR" ${lib.getExe pkgs.opentelemetry-collector-contrib} validate \
              --config=${telemetry.collectorConfigFile}
            touch "$out"
          '';

      checks."codex/config" =
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
            mkdir -p "$PWD/generated"
            ln -s ${runtime.baseConfigFile} "$PWD/generated/config.base.toml"
            ln -s ${runtime.nixProjectsFile} "$PWD/generated/projects.nix.toml"
            uv run --no-project ${./_config-check.py} \
              ${lib.getExe codexPkg} ${lib.getExe runtime.codexWrapped}
            touch "$out"
          '';
    };
}

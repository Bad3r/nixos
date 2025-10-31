/*
  Package: uv
  Description: Fast Python package installer and resolver written in Rust (Astral’s uv).
  Homepage: https://github.com/astral-sh/uv
  Documentation: https://docs.astral.sh/uv/
  Repository: https://github.com/astral-sh/uv

  Summary:
    * Replaces pip and pip-tools with a single tool for dependency resolution, installation, lockfiles, and syncing virtual environments.
    * Implements PEP 517/518 builds, pyproject.toml parsing, and cross-platform caching with high performance.

  Options:
    uv pip install <pkg>: Install packages with uv’s resolver (drops in for pip).
    uv lock: Resolve and generate a lockfile (`uv.lock`) for deterministic installs.
    uv sync: Sync dependencies into a virtual environment based on lockfile/project config.
    uv run <cmd>: Execute commands inside managed environments.
    uv tool install <pkg>: Install standalone CLI tools into an isolated environment.

  Example Usage:
    * `uv pip install requests` — Install a Python package using uv instead of pip.
    * `uv lock {PRESERVED_DOCUMENTATION}{PRESERVED_DOCUMENTATION} uv sync` — Produce a lockfile and sync dependencies into `.venv`.
    * `uv run pytest` — Execute a command using the synced environment without manually activating it.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.uv.extended;
  UvModule = {
    options.programs.uv.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to enable uv.";
      };

      package = lib.mkPackageOption pkgs "uv" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.uv = UvModule;
}

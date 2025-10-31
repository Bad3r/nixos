/*
  Package: lazydocker
  Description: Simple terminal UI for both docker and docker-compose.
  Homepage: https://github.com/jesseduffield/lazydocker
  Documentation: https://github.com/jesseduffield/lazydocker#readme
  Repository: https://github.com/jesseduffield/lazydocker

  Summary:
    * Provides an ncurses-style dashboard for inspecting containers, images, volumes, and compose projects.
    * Supports log streaming, resource metrics, shell entry, and command execution without typing long docker commands.

  Options:
    --config <file>: Use a custom YAML configuration (default `~/.config/lazydocker/config.yml`).
    --debug: Enable verbose logging to diagnose issues.
    --version: Print the client version and exit.
    -H <host>: Connect to a remote Docker host via DOCKER_HOST syntax.

  Example Usage:
    * `lazydocker` — Explore running containers, view logs, and manage compose stacks from the terminal.
    * `lazydocker --config ~/.config/lazydocker/team.yml` — Apply shared team settings and shortcuts.
    * `DOCKER_HOST=ssh://ops@prod.example.com lazydocker` — Inspect containers on a remote host over SSH.
*/

{
  flake.homeManagerModules.apps.lazydocker =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.lazydocker.extended;
    in
    {
      options.programs.lazydocker.extended = {
        enable = lib.mkEnableOption "Simple terminal UI for both docker and docker-compose.";
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.lazydocker ];
      };
    };
}

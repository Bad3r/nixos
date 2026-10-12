/*
  Package: magnitude
  Description: Local inference engine for agents that tunes its kernels to the host hardware.
  Homepage: https://magnitude.dev
  Documentation: https://docs.magnitude.dev
  Repository: https://github.com/magnitudedev/magnitude

  Summary:
    * Downloads open models and serves them to agent harnesses such as Claude Code and Codex.
    * Compiles and tunes its inference kernels for the local CPU, CUDA, or Vulkan device.

  Options:
    app: Open the Magnitude desktop application.
    serve: Run Magnitude in the foreground.
    status: Show the Magnitude owner, service, and active-model status.
    hardware: Show hardware and memory available to local inference.
    catalog: Find, compare, and download local models.
    models: Inspect and control local models on this computer.
    connections: Connect Magnitude models to agent harnesses.

  Notes:
    * Package sourced from llm-agents.nix flake (github:Bad3r/llm-agents.nix).
    * The bundled desktop-host.node refuses `magnitude serve` and the desktop app until
      /var/lib/magnitude-desktop/installation.lock exists, root-owned and mode 0444, as the
      upstream deb's preinst creates it.
*/
{ inputs, ... }:
{
  flake.nixosModules.apps.magnitude =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.magnitude.extended;
    in
    {
      options.programs.magnitude.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Magnitude.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.magnitude;
          defaultText = lib.literalExpression "inputs.llm-agents.packages.\${system}.magnitude";
          description = "The Magnitude package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        systemd.tmpfiles.settings.magnitude = {
          "/var/lib/magnitude-desktop".d = {
            mode = "0755";
            user = "root";
            group = "root";
          };
          "/var/lib/magnitude-desktop/installation.lock".f = {
            mode = "0444";
            user = "root";
            group = "root";
          };
        };
      };
    };
}

/*
  Package: logseq
  Description: Knowledge management and collaboration tool
  Homepage: https://logseq.com/
  Documentation: https://docs.logseq.com/
  Repository: https://github.com/logseq/logseq

  Summary:
    * A privacy-first, open-source platform for knowledge sharing and management.
    * Supports outlining, note-taking, and graph visualization.

  Options:
    logseq: Launch the desktop application.

  Example Usage:
    * `logseq` — Open the Logseq desktop app.
*/
{ inputs, ... }:
let
  LogseqModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.logseq.extended;
      basePackage = inputs.nix-logseq-git-flake.packages.${pkgs.stdenv.hostPlatform.system}.logseq;
      # Wrap with --disable-gpu-compositing for NVIDIA PRIME sync compatibility
      wrappedPackage = pkgs.writeShellScriptBin "logseq" ''
        exec ${basePackage}/bin/logseq --disable-gpu-compositing "$@"
      '';
      finalPackage = pkgs.symlinkJoin {
        name = "logseq-wrapped";
        paths = [
          wrappedPackage
          basePackage
        ];
        # Ensure the wrapper takes precedence
        postBuild = ''
          rm $out/bin/logseq
          cp ${wrappedPackage}/bin/logseq $out/bin/logseq
        '';
      };
    in
    {
      options.programs.logseq.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Logseq.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = basePackage;
          description = "The Logseq package to use.";
        };

        disableGpuCompositing = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Pass --disable-gpu-compositing to work around blank screen on NVIDIA PRIME sync.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [
          (if cfg.disableGpuCompositing then finalPackage else cfg.package)
        ];
      };
    };
in
{
  flake.nixosModules.apps.logseq = LogseqModule;
}

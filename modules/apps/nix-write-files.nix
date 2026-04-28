/*
  Package: nix-write-files
  Description: Convenience wrapper around `nix develop --offline -c write-files`.

  Summary:
    * Invokes the dev shell's `write-files` writer in offline mode so flag order
      mistakes do not cause `nix` to contact substituters during evaluation.
    * Forwards positional arguments to the underlying writer.

  Usage:
    Run from anywhere inside the flake's worktree:

        nix-write-files

    Any extra arguments are passed through to `write-files`.
*/
_:
let
  NixWriteFilesModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.nix-write-files.extended;
    in
    {
      options.programs.nix-write-files.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to install the nix-write-files wrapper.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.writeShellApplication {
            name = "nix-write-files";
            runtimeInputs = [ config.nix.package ];
            text = ''
              exec nix develop --offline -c write-files "$@"
            '';
          };
          defaultText = lib.literalExpression "pkgs.writeShellApplication { name = \"nix-write-files\"; ... }";
          description = "Derivation providing the nix-write-files wrapper.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.nix-write-files = NixWriteFilesModule;
}

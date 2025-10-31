/*
  Package: file
  Description: Utility that identifies file types using libmagic pattern matching.
  Homepage: https://darwinsys.com/file/
  Documentation: https://man.archlinux.org/man/file.1.en
  Repository: https://github.com/file/file

  Summary:
    * Detects file formats by inspecting magic numbers, MIME types, and encoding heuristics.
    * Supports custom magic databases to recognize organization-specific file signatures.

  Options:
    -i <path>: Print MIME type strings alongside file names.
    -L <path>: Follow symlinks before identifying the target file.
    -z <path>: Inspect compressed files by decompressing them in memory.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.file.extended;
  FileModule = {
    options.programs.file.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true; # Backward compatibility - TODO: flip to false in Phase 2
        description = lib.mdDoc "Whether to enable file.";
      };

      package = lib.mkPackageOption pkgs "file" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.file = FileModule;
}

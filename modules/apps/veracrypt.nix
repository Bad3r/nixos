/*
  Package: veracrypt
  Description: Disk encryption software for creating and mounting encrypted volumes and full-disk encryption.
  Homepage: https://www.veracrypt.fr/
  Documentation: https://www.veracrypt.fr/en/Documentation.html
  Repository: https://www.veracrypt.fr/code/VeraCrypt

  Summary:
    * Successor to TrueCrypt offering encrypted containers, whole-disk encryption, hidden volumes, and hardware-accelerated ciphers.
    * Provides both GUI and CLI (`veracrypt`) for creating volumes, mounting them, changing passwords, and handling keyfiles.

  Options:
    veracrypt --text --create <file>: Create a new encrypted container via CLI prompts.
    veracrypt --mount <file> <mountpoint>: Mount an encrypted volume.
    veracrypt --dismount <mountpoint|volume>: Unmount a mounted volume.
    veracrypt --password <pass> --keyfiles <file>: Supply credentials non-interactively (use cautiously).

  Example Usage:
    * `veracrypt` — Launch the GUI to create or mount encrypted volumes.
    * `veracrypt --text --create secret.hc --size 500M --encryption AES` — Create a 500 MB container from the terminal.
    * `veracrypt --text --mount secret.hc /mnt/secure` — Mount an existing container to a directory.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.veracrypt.extended;
  VeracryptModule = {
    options.programs.veracrypt.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to enable veracrypt.";
      };

      package = lib.mkPackageOption pkgs "veracrypt" { };
    };

    config = lib.mkIf cfg.enable {
      nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "veracrypt" ];

      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.veracrypt = VeracryptModule;
}

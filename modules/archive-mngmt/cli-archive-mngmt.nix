{ lib, ... }:
{
  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      # PC-specific audio packages
      environment.systemPackages =
        with pkgs;
        lib.mkDefault [
          gzip
          bzip2
          xz
          gnutar
          p7zip-rar # 7zip w/ support for rar
          rar
          unrar
          zip
          unzip
        ];
    };
}

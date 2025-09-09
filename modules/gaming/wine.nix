{
  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        # Wine staging - the latest development version with experimental features
        wine-staging
        # Additional Wine tools
        winetricks
        # 32-bit support for Wine
        wineWowPackages.staging
      ];
    };
}

_: {
  flake.nixosModules.pc =
    { lib, ... }:
    {
      # Fix qt.platformTheme compatibility between home-manager and nixos
      # Home-manager tries to set "kde6" but nixos only accepts "kde"
      qt.platformTheme = lib.mkForce "kde";
    };
}

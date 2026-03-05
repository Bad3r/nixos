{
  nixpkgs.allowedUnfreePackages = [ "teamviewer" ];

  configurations.nixos.tpnix.module = {
    services.teamviewer.enable = false;
  };
}

{
  nixpkgs.allowedUnfreePackages = [ "teamviewer" ];

  configurations.nixos.tec.module = {
    services.teamviewer.enable = true;
  };
}

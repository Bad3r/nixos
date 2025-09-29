{
  nixpkgs.allowedUnfreePackages = [ "teamviewer" ];

  configurations.nixos.system76.module = {
    services.teamviewer.enable = false;
  };
}

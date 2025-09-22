{
  nixpkgs.allowedUnfreePackages = [ "electron-mail" ];

  flake.nixosModules.apps."electron-mail" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.electron-mail ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.electron-mail ];
    };
}

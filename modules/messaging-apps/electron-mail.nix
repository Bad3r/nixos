{
  nixpkgs.allowedUnfreePackages = [
    "electron-mail"
  ];

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        electron-mail
      ];
    };
}

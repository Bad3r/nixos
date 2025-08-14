{
  nixpkgs.allowedUnfreePackages = [
    "electron-mail"
  ];

  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        electron-mail
      ];
    };
}

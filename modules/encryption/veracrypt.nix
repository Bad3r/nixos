{
  nixpkgs.allowedUnfreePackages = [
    "veracrypt"
  ];

  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        veracrypt
      ];
    };
}

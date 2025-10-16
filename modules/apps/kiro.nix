{
  flake.nixosModules.apps."kiro" =
    { pkgs, ... }:
    {
      nixpkgs.allowedUnfreePackages = [ "kiro-fhs" ];
      environment.systemPackages = [ pkgs."kiro-fhs" ];
    };
}

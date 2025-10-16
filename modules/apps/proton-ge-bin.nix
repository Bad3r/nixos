{
  flake.nixosModules.apps."proton-ge-bin" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."proton-ge-bin" ];
    };
}

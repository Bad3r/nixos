{
  flake.nixosModules.apps."mpv-shim-default-shaders" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."mpv-shim-default-shaders" ];
    };
}

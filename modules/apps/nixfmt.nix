{
  flake.nixosModules.apps."nixfmt" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."nixfmt" ];
    };
}

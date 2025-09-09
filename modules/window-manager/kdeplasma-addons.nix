{
  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.kdePackages.kdeplasma-addons ];
    };
}

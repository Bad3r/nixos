_: {
  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.cosmic-term ];
    };
}

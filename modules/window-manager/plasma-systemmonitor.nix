{
  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.kdePackages.plasma-systemmonitor ];
    };
}

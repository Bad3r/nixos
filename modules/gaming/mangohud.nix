{
  flake.modules = {
    # Install MangoHud package at system level
    nixos.pc =
      { pkgs, ... }:
      {
        environment.systemPackages = [ pkgs.mangohud ];
      };

    # Enable MangoHud in Home Manager with Stylix theme integration
    homeManager.gui = _: {
      programs.mangohud = {
        enable = true;
        # Stylix will automatically apply the color scheme to MangoHud
        # when both are enabled in the same configuration
      };
    };
  };
}

{
  flake =
    let
      mangohudModule =
        { pkgs, ... }:
        {
          environment.systemPackages = [ pkgs.mangohud ];
        };
    in
    {
      nixosModules = {
        pc = mangohudModule;
        apps.mangohud = mangohudModule;
      };

      # Enable MangoHud in Home Manager with Stylix theme integration
      homeManagerModules.gui = _: {
        programs.mangohud = {
          enable = true;
          # Stylix will automatically apply the color scheme to MangoHud
          # when both are enabled in the same configuration
        };
      };
    };
}

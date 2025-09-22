{
  flake = {
    nixosModules.apps.mangohud =
      { pkgs, ... }:
      {
        environment.systemPackages = [ pkgs.mangohud ];
      };

    nixosModules.pc =
      { pkgs, ... }:
      {
        environment.systemPackages = [ pkgs.mangohud ];
      };

    homeManagerModules.gui = _: {
      programs.mangohud.enable = true;
    };
  };
}

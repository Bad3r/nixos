{
  flake = {
    nixosModules.apps.lutris =
      { pkgs, ... }:
      {
        environment.systemPackages = [ pkgs.lutris ];
      };

    homeManagerModules.apps.lutris = _: {
      programs.lutris.enable = true;
    };

    homeManagerModules.gui = _: {
      programs.lutris.enable = true;
    };
  };
}

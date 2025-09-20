{
  flake = {
    nixosModules.apps.lutris =
      { pkgs, ... }:
      {
        environment.systemPackages = [ pkgs.lutris ];
      };

    homeManagerModules.gui = _: {
      programs.lutris = {
        enable = true;
        # Lutris provides support for various game sources and runners
        # including Wine, native Linux games, emulators, etc.
      };
    };
  };
}

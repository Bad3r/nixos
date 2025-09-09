{
  flake = {
    nixosModules.efi.boot.loader = {
      systemd-boot = {
        enable = true;
        editor = false;
        consoleMode = "auto";
        configurationLimit = 3;
      };
      efi.canTouchEfiVariables = true;
    };

    homeManagerModules.base =
      { pkgs, ... }:
      {
        home.packages = [
          pkgs.efivar
          pkgs.efibootmgr
        ];
      };
  };
}

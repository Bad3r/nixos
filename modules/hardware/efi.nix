{
  flake.modules = {
    nixos.efi.boot.loader = {
      systemd-boot = {
        enable = true;
        editor = false;
        consoleMode = "auto";
        configurationLimit = 3;
      };
      efi.canTouchEfiVariables = true;
    };

    homeManager.base =
      { pkgs, ... }:
      {
        home.packages = [
          pkgs.efivar
          pkgs.efibootmgr
        ];
      };
  };
}

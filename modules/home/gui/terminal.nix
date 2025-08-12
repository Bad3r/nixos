{ lib, ... }:
{
  flake.modules.homeManager = {
    base =
      { pkgs, ... }:
      {
        options.terminal = {
          path = lib.mkOption {
            type = lib.types.path;
            default = null;
          };
          withTitle = lib.mkOption {
            type = lib.types.functionTo lib.types.str;
            default = null;
          };
        };

        config.home.packages = with pkgs; [ ansifilter ];
      };
    gui =
      { config, pkgs, ... }:
      {
        terminal = {
          path = lib.getExe config.programs.kitty.package;
          withTitle = cmd: "${config.terminal.path} --title ${cmd} ${cmd}";
        };

        # Note: Ghostty terminal will be added when it becomes available in nixpkgs
        programs.kitty = {
          enable = true;
          # theme option changed to themeFile in newer versions
          # Using stylix for theming instead
          settings = {
            background_opacity = lib.mkDefault "0.9";
            enable_audio_bell = false;
            update_check_interval = 0;
          };
        };

        stylix.targets.kitty.enable = true;
      };
  };
}

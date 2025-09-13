{ lib, inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks = {
        "home-manager/base" =
          let
            hm = inputs.home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [
                {
                  home.username = "hm-smoke";
                  home.homeDirectory = "/tmp/hm-smoke";
                  programs.home-manager.enable = true;
                }
                { home.stateVersion = "25.05"; }
              ];
            };
          in
          lib.getAttrFromPath [ "config" "home-files" ] hm;

        "home-manager/gui" =
          let
            hm = inputs.home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [
                {
                  home.username = "hm-smoke";
                  home.homeDirectory = "/tmp/hm-smoke";
                  programs.home-manager.enable = true;
                  programs.alacritty.enable = true;
                }
                { home.stateVersion = "25.05"; }
              ];
            };
          in
          lib.getAttrFromPath [ "config" "home-files" ] hm;
      };
    };
}

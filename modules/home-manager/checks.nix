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
                  home = {
                    username = "hm-smoke";
                    homeDirectory = "/tmp/hm-smoke";
                    stateVersion = (lib.importJSON "${inputs.home-manager}/release.json").release;
                    enableNixpkgsReleaseCheck = false;
                  };
                  programs.home-manager.enable = true;
                }
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
                  home = {
                    username = "hm-smoke";
                    homeDirectory = "/tmp/hm-smoke";
                    stateVersion = (lib.importJSON "${inputs.home-manager}/release.json").release;
                    enableNixpkgsReleaseCheck = false;
                  };
                  programs.home-manager.enable = true;
                  programs.alacritty.enable = true;
                }
              ];
            };
          in
          lib.getAttrFromPath [ "config" "home-files" ] hm;
      };
    };
}

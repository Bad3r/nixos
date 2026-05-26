{ lib, inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      smokeOsConfig.system.stateVersion = (lib.importJSON "${inputs.home-manager}/release.json").release;

      stateVersionModule =
        { osConfig, ... }:
        {
          home.stateVersion = osConfig.system.stateVersion;
          home.enableNixpkgsReleaseCheck = false;
        };
    in
    {
      checks = {
        "home-manager/base" =
          let
            hm = inputs.home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              extraSpecialArgs.osConfig = smokeOsConfig;
              modules = [
                {
                  home.username = "hm-smoke";
                  home.homeDirectory = "/tmp/hm-smoke";
                  programs.home-manager.enable = true;
                }
                stateVersionModule
              ];
            };
          in
          lib.getAttrFromPath [ "config" "home-files" ] hm;

        "home-manager/gui" =
          let
            hm = inputs.home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              extraSpecialArgs.osConfig = smokeOsConfig;
              modules = [
                {
                  home.username = "hm-smoke";
                  home.homeDirectory = "/tmp/hm-smoke";
                  programs.home-manager.enable = true;
                  programs.alacritty.enable = true;
                }
                stateVersionModule
              ];
            };
          in
          lib.getAttrFromPath [ "config" "home-files" ] hm;
      };
    };
}

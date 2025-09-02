{
  config,
  lib,
  inputs,
  ...
}:
{
  perSystem =
    { pkgs, ... }:
    {
      checks =
        lib.mapAttrs'
          (name: modules: {
            name = "home-manager/${name}";
            value =
              lib.getAttrFromPath
                [
                  "config"
                  "home-files"
                ]
                (
                  inputs.home-manager.lib.homeManagerConfiguration {
                    inherit pkgs;
                    modules = modules ++ [ { home.stateVersion = "25.05"; } ];
                  }
                );
          })
          {
            base = with config.flake.modules.homeManager; [ base ];
            gui = with config.flake.modules.homeManager; [
              base
              gui
            ];
          };
    };
}

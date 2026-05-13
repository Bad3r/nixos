_:
let
  body = {
    xdg = {
      menus.enable = true;
      mime.enable = true;
      # Browser defaults are set through host.defaults.browser.
      # User-level ~/.config/mimeapps.list always overrides system-level
    };
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}

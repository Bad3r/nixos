# Module: home/base/xdg-mime.nix
# Purpose: Xdg Mime configuration
# Namespace: flake.modules.homeManager.base
# Pattern: Home Manager base - CLI and terminal environment

# modules/xdg-mime.nix

{
  flake.modules.homeManager.base.xdg = {
    enable = true;
    mime.enable = true;
    mimeApps = {
      enable = true;
      defaultApplications = {
        #"application/pdf" = "org.pwmt.zathura.desktop";
      };
    };
  };
}

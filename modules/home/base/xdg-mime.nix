
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

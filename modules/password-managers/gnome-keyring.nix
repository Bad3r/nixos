_: {
  flake.homeManagerModules.gnomeKeyringBackend = {
    services.gnome-keyring.enable = true;
  };
}

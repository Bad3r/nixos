{
  flake.nixosModules.workstation = _: {
    services.gnome.gnome-keyring.enable = true;
    security.pam.services.login.enableGnomeKeyring = true;
  };

  flake.homeManagerModules.base = _: {
    services.pass-secret-service.enable = true;
  };
}

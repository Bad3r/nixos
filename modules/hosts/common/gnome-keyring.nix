_:
let
  body = {
    # The NixOS module brings the org.freedesktop.secrets D-Bus activation, the
    # gcr prompter, the cap_ipc_lock wrapper, and the login PAM unlock that
    # LightDM's stacks substack; a Home Manager user unit adds none of these.
    services.gnome.gnome-keyring.enable = true;

    # Defaults to gnome-keyring's value, and its socket unit sets SSH_AUTH_SOCK in
    # the user manager; gpg-agent owns that socket here (programs.gnupg.agent.enableSSHSupport).
    services.gnome.gcr-ssh-agent.enable = false;
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}

{ lib, ... }:
let
  body = {
    services.gnome.gnome-keyring.enable = lib.mkDefault true;
    # Not a default: gcr's socket unit sets SSH_AUTH_SOCK, which would displace the 1Password agent.
    services.gnome.gcr-ssh-agent.enable = false;
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}

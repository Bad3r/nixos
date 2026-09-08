_:
let
  body = {
    services.gnome.gnome-keyring.enable = true;
    services.gnome.gcr-ssh-agent.enable = false;
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}

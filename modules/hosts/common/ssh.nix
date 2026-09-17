_:
let
  body = {
    services.openssh.settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PubkeyAuthentication = true;
      PermitRootLogin = "no";
    };
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}

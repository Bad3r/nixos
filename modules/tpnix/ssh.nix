{ lib, ... }:
{
  configurations.nixos.tpnix.module = _: {
    # Harden SSH settings; leave host public key unset until this host key is declared.
    services.openssh = {
      settings = {
        PasswordAuthentication = lib.mkDefault false;
        PermitRootLogin = lib.mkDefault "no";
      };
    };
  };
}

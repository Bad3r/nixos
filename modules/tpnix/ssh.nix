{ lib, ... }:
{
  configurations.nixos.tpnix.module = _: {
    services.openssh = {
      settings = {
        PasswordAuthentication = true;
        PermitRootLogin = lib.mkDefault "no";
      };
    };
  };
}

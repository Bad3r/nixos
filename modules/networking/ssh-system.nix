_:
{
  # Keep SSH server available but restrict authentication to keys only and block root logins.
  # We purposely avoid global IdentityAgent tweaks so SSH continues to honour SSH_AUTH_SOCK;
  # Home Manager config is responsible for pointing clients at the gpg-agent socket.
  flake.nixosModules.base =
    { lib, ... }:
    {
      services.openssh = {
        enable = lib.mkDefault true;
        openFirewall = lib.mkDefault true;
        settings = {
          PasswordAuthentication = false;
          ChallengeResponseAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = "no";
        };
      };
    };
}

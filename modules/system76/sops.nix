{ lib, ... }:
{
  configurations.nixos.system76.module = _: {
    config = {
      sops = {
        age = {
          keyFile = lib.mkForce "/var/lib/sops-nix/key.txt";
          sshKeyPaths = lib.mkForce [ ];
        };
        gnupg.sshKeyPaths = lib.mkForce [ ];
      };
    };
  };
}

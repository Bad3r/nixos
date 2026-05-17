{ lib, ... }:
let
  body = _: {
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
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}

{ inputs, ... }:
{
  flake.nixosModules.sopsRuntime =
    { lib, ... }:
    {
      imports = [ inputs.sops-nix.nixosModules.sops ];

      sops.age.keyFile = lib.mkForce "/var/lib/sops-nix/key.txt";
      sops.age.sshKeyPaths = lib.mkForce [ ];
    };
}

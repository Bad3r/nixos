{ inputs, ... }:
{
  flake.nixosModules.sopsRuntime =
    {
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ inputs.sops-nix.nixosModules.sops ];

      environment.systemPackages = with pkgs; [
        age
        sops
      ];

      sops.age.keyFile = lib.mkForce "/var/lib/sops-nix/key.txt";
      sops.age.sshKeyPaths = lib.mkForce [ ];
    };
}

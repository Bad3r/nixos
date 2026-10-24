{
  flake.nixosModules.repoSecrets =
    { lib, ... }:
    {
      options.security.repoSecrets.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether app modules declare their repository-managed system SOPS secrets.";
      };
    };
}

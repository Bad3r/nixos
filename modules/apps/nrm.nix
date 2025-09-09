{
  flake.nixosModules.apps.nrm =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        (pkgs.writeShellScriptBin "nrm" ''
          exec ${pkgs.nodejs_22}/bin/npx -y nrm "$@"
        '')
      ];
    };
}

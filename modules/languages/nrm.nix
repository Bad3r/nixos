{
  flake.modules.nixos.workstation =
    { pkgs, ... }:
    let
      nrm = pkgs.writeShellScriptBin "nrm" ''
        exec ${pkgs.nodejs_22}/bin/npx -y nrm "$@"
      '';
    in
    {
      environment.systemPackages = [ nrm ];
    };
}

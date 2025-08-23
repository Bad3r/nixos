{
  flake.modules.nixos.workstation =
    { pkgs, ... }:
    let
      nrm = pkgs.writeShellScriptBin "nrm" ''
        exec ${pkgs.nodejs_22}/bin/npx -y nrm "$@"
      '';
    in
    {
      environment.systemPackages = with pkgs; [
        nodejs_22
        nodejs_24
        yarn
        nrm
      ];
    };
}

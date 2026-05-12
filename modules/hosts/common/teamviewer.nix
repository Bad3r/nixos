_:
let
  body = {
    services.teamviewer.enable = false;
  };
in
{
  nixpkgs.allowedUnfreePackages = [ "teamviewer" ];

  flake.nixosModules.hosts-common.imports = [ body ];
}

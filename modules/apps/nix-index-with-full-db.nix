{
  config,
  pkgs,
  ...
}:
let
  inputs = config._module.args.inputs or { };
  databasePkg =
    if inputs ? nix-index-database then
      inputs.nix-index-database.packages.${pkgs.system}.nix-index-with-db
    else
      throw "nix-index-with-full-db app requires nix-index-database input";
in
{
  flake.nixosModules.apps."nix-index-with-full-db" = _: {
    environment.systemPackages = [ databasePkg ];
  };
}

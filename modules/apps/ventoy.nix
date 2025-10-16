{
  flake.nixosModules.apps."ventoy" =
    { pkgs, lib, ... }:
    {
      nixpkgs.config.permittedInsecurePackages = lib.mkAfter [ (lib.getName pkgs.ventoy) ];
      nixpkgs.config.allowInsecurePredicate = lib.mkDefault (pkg: lib.getName pkg == "ventoy");
      environment.systemPackages = [ pkgs.ventoy ];
    };
}

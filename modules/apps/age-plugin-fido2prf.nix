{
  flake.nixosModules.apps."age-plugin-fido2prf" =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      packageSet = lib.attrByPath [ pkgs.system ] { } (config.flake.packages or { });
      agePlugin = lib.attrByPath [ "age-plugin-fido2prf" ] (pkgs.callPackage
        ../../packages/age-plugin-fido2prf
        { }
      ) packageSet;
    in
    {
      environment.systemPackages = [ agePlugin ];
    };
}

/*
  Package: burpsuite-loader
  Description: Burp Suite Professional license loader.
  Homepage: https://portswigger.net/
  Documentation: https://portswigger.net/burp/documentation
  Repository: https://github.com/Bad3r/nixos
*/
_:
let
  BurpsuiteLoaderModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."burpsuite-loader".extended;
      burpsuiteLoaderPackage = pkgs.writeShellApplication {
        name = "burpsuite-loader";
        text = ''
          exec ${lib.getExe' pkgs.burpsuitepro "loader"} "$@"
        '';
      };
    in
    {
      options.programs."burpsuite-loader".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable burpsuite-loader.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = burpsuiteLoaderPackage;
          defaultText = lib.literalExpression "generated burpsuite-loader wrapper package";
          description = "The burpsuite-loader package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."burpsuite-loader" = BurpsuiteLoaderModule;
}

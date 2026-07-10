/*
  Package: tinfoil-wiper
  Description: Securely erase NVMe SSDs with controller-native or software methods
  Homepage: https://github.com/Bad3r/Tinfoil-Wiper
  Repository: https://github.com/Bad3r/Tinfoil-Wiper

  Usage:
    * `tinfoil_wiper --dry-run /dev/nvme0n1` -- Preview an erase plan.
    * `sudo tinfoil_wiper /dev/nvme0n1` -- Run the selected erase method.

  The package grants no privileges. Real wipes still require an explicit root
  invocation.
*/
{ inputs, ... }:
let
  TinfoilWiperModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."tinfoil-wiper".extended;
    in
    {
      options.programs."tinfoil-wiper".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Tinfoil Wiper.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.tinfoil-wiper.packages.${pkgs.stdenv.hostPlatform.system}.tinfoil-wiper;
          defaultText = lib.literalExpression "inputs.tinfoil-wiper.packages.\${pkgs.stdenv.hostPlatform.system}.tinfoil-wiper";
          description = "The Tinfoil Wiper package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."tinfoil-wiper" = TinfoilWiperModule;
}

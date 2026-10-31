/*
  Package: hopper
  Description: MacOS and Linux Disassembler for reverse engineering Mach-O and other binary formats.
  Homepage: https://www.hopperapp.com/
  Documentation: https://www.hopperapp.com/tutorial.html
  Repository: nil

  Summary:
    * Supports Mach-O format analysis including Objective-C class structures
    * Provides scripting capabilities for automated analysis

  Options:
    --executable <path>: Specify the binary file to analyze
    --python <script.py>: Run a Python script after the initial analysis
*/
_:
let
  HopperModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.hopper.extended;
    in
    {
      options.programs.hopper.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable hopper.";
        };

        package = lib.mkPackageOption pkgs "hopper" { };
      };

      config = lib.mkIf cfg.enable {

        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "hopper" ];
  flake.nixosModules.apps.hopper = HopperModule;
}

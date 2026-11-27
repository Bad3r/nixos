/*
  Package: ida-pro
  Description: Hex-Rays IDA Pro disassembler and decompiler with IDA Assist, packaged by ida-nix.
  Homepage: https://hex-rays.com/ida-pro
  Documentation: https://docs.hex-rays.com/
  Repository: https://github.com/Bad3r/ida-nix

  Summary:
    * Installs `idapro-sandbox`, `idat`, `ida-mcp`, and `ida-sandbox`, each running in a bubblewrap sandbox, plus `idapro` (IDA with the IDA Assist plugin) and `assist-mcp`, which run unsandboxed because the IDA Assist plugin accepts its MCP bridge only from its own user namespace.

  Notes:
    * Every vendor file is a `requireFile` source: run `scripts/ida-setup` from the ida-nix repository once per machine to add them to the Nix store and install the license.
    * The package comes from the ida-nix flake output, which carries its own unfree allowlist.
*/
{ inputs, ... }:
let
  IdaProModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."ida-pro".extended;
    in
    {
      options.programs."ida-pro".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable IDA Pro.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.ida-nix.packages.${pkgs.stdenv.hostPlatform.system}.ida-pro;
          defaultText = lib.literalExpression "inputs.ida-nix.packages.\${pkgs.stdenv.hostPlatform.system}.ida-pro";
          description = "The IDA Pro package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."ida-pro" = IdaProModule;
}

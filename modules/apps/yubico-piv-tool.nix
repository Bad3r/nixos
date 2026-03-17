/*
  Package: yubico-piv-tool
  Description: Used for interacting with the Privilege and Identification Card (PIV) application on a YubiKey.
  Homepage: https://developers.yubico.com/yubico-piv-tool/
  Documentation: https://developers.yubico.com/yubico-piv-tool/
  Repository: https://github.com/Yubico/yubico-piv-tool

  Summary:
    * Manages the YubiKey PIV application for key generation, import, attestation, and certificate workflows.
    * Supports reader selection, slot targeting, algorithm choice, and encrypted management sessions.

  Options:
    -a, --action=ENUM: Choose the PIV action to execute, such as generate, import-key, attest, or read-certificate.
    -s, --slot=ENUM: Select the PIV slot to operate on.
    -A, --algorithm=ENUM: Choose the algorithm for key generation or import.
    -i, --input=STRING: Read key or certificate input from a file or stdin.
    -o, --output=STRING: Write command output to a file or stdout.
    --pin-policy=ENUM: Set the PIN policy for key generation or import-key actions.
    --touch-policy=ENUM: Set the touch policy for supported actions on newer keys.
    --enc: Communicate with the YubiKey over an encrypted channel.
*/
_:
let
  YubicoPivToolModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.yubico-piv-tool.extended;
    in
    {
      options.programs.yubico-piv-tool.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable yubico-piv-tool.";
        };

        package = lib.mkPackageOption pkgs "yubico-piv-tool" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.yubico-piv-tool = YubicoPivToolModule;
}

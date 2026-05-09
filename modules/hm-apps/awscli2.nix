/*
  Package: awscli2
  Description: Home Manager glue for AWS CLI v2 config and credentials.
  Homepage: https://aws.amazon.com/cli/
  Documentation: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html
  Repository: https://github.com/aws/aws-cli

  Summary:
    * Enables the upstream `programs.awscli` Home Manager module when the NixOS counterpart is enabled.
    * Lets the NixOS module own the package install; HM only manages `~/.aws/config` and `~/.aws/credentials` content.

  Notes:
    * Upstream HM `programs.awscli.package` defaults to `awscli2` and is nullable, so `package = null` avoids a duplicate store path.
*/
_: {
  flake.homeManagerModules.apps.awscli2 =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "awscli2" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.awscli = {
          enable = true;
          package = null;
        };
      };
    };
}

/*
  Package: 1password-gui
  Description: 1Password desktop password manager.
  Homepage: https://1password.com/
  Documentation: https://support.1password.com/getting-started-linux/
  Repository: nil

  Notes:
    * Stable release channel.
    * Configures browser integration
*/
_:
let
  OnePasswordGuiModule =
    {
      config,
      lib,
      metaOwner,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."1password-gui".extended;
      owner = metaOwner.username;
      browserEnabled = name: lib.attrByPath [ "programs" name "extended" "enable" ] false config;
      customAllowedBrowsers =
        lib.optional (browserEnabled "librewolf") "librewolf"
        ++ lib.optional (browserEnabled "firefox") "firefox"
        ++ lib.optional (browserEnabled "mullvad-browser") "mullvad-browser";
    in
    {
      options.programs."1password-gui".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enables 1Password desktop App.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs._1password-gui;
          defaultText = lib.literalExpression "pkgs._1password-gui";
          description = "The 1Password GUI package to use.";
        };

        polkitPolicyOwners = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ owner ];
          description = "Users allowed to integrate 1Password with polkit.";
        };
      };

      config = lib.mkIf cfg.enable {
        programs._1password-gui = {
          enable = true;
          inherit (cfg) package polkitPolicyOwners;
        };

        environment.etc."1password/custom_allowed_browsers" = lib.mkIf (customAllowedBrowsers != [ ]) {
          text = lib.concatStringsSep "\n" customAllowedBrowsers + "\n";
          mode = "0644";
        };
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "1password" ];
  flake.nixosModules.apps."1password-gui" = OnePasswordGuiModule;
}

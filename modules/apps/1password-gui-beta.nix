/*
  Package: 1password-gui-beta
  Description: Beta channel of the 1Password desktop password manager.
  Homepage: https://1password.com/
  Documentation: https://support.1password.com/getting-started-linux/
  Repository: nil

  Summary:
    * Installs the 1Password Linux desktop application from the beta release channel.
    * Provides vault browsing, item editing, browser integration, Quick Access, and Watchtower checks.

  Options:
    Browser integration: Connect supported browsers to the desktop app for unlock and filling workflows.
    Quick Access: Fill credentials in desktop apps from the Linux client.
    Watchtower: Review reused, weak, or compromised passwords and other security alerts.

  Notes:
    * Uses nixpkgs package `pkgs._1password-gui` with the beta channel; the app key omits the leading underscore for repo module discovery.
    * Delegates browser-support wrapper setup to nixpkgs' `programs._1password-gui` module.
*/
_:
let
  OnePasswordGuiBetaModule =
    {
      config,
      lib,
      metaOwner,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."1password-gui-beta".extended;
      owner = metaOwner.username;
      browserEnabled = name: lib.attrByPath [ "programs" name "extended" "enable" ] false config;
      customAllowedBrowsers =
        lib.optional (browserEnabled "floorp") "floorp"
        ++ lib.optional (browserEnabled "librewolf") "librewolf"
        ++ lib.optional (browserEnabled "firefox") "firefox"
        ++ lib.optional (browserEnabled "mullvad-browser") "mullvad-browser";
    in
    {
      options.programs."1password-gui-beta".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable 1password-gui-beta.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs._1password-gui.override {
            channel = "beta";
          };
          defaultText = lib.literalExpression ''
            pkgs._1password-gui.override {
              channel = "beta";
            }
          '';
          description = "The 1Password GUI beta package to use.";
        };

        polkitPolicyOwners = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ owner ];
          description = "Users allowed to integrate 1Password with polkit-based authentication mechanisms.";
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
  flake.nixosModules.apps."1password-gui-beta" = OnePasswordGuiBetaModule;
}

/*
  Package: firefoxpwa
  Description: Progressive Web Apps for Firefox (PWAsForFirefox). Installs and
    runs websites as standalone apps in a dedicated, patched Firefox runtime,
    managed from the browser through a companion extension and native connector.
  Homepage: https://pwasforfirefox.filips.si/
  Repository: https://github.com/filips123/PWAsForFirefox

  Notes:
    * The companion extension and native-messaging connector are wired into the
      gecko browsers in modules/browsers/{firefox,librewolf}/home.nix.
    * Extensions for the isolated PWA runtime profiles are installed (per-add-on
      force_installed or user-removable normal_installed) through a policy file
      injected by modules/custom-overlays/firefoxpwa.nix.
*/
_:
let
  FirefoxpwaModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.firefoxpwa.extended;
      m365Cfg = config.programs.firefoxpwa.m365;
      m365Keys = map (app: app.key) m365Cfg.apps;
      m365Names = map (app: app.name) m365Cfg.apps;
      duplicates = xs: lib.unique (lib.filter (x: lib.count (y: y == x) xs > 1) xs);
    in
    {
      options.programs.firefoxpwa = {
        extended = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether to enable Progressive Web Apps for Firefox.";
          };

          package = lib.mkPackageOption pkgs "firefoxpwa" { };
        };

        # Per-site install toggles are declared here (NixOS scope) so the common
        # app catalog and per-host apps-enable files can layer them like any other
        # app, and the Home Manager installer in ./dmail.nix can read them through
        # `osConfig`.
        dmail.enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Install the primary user's work mail Progressive Web App (DMail)
            through firefoxpwa. The start URL is read at runtime from the
            SOPS-encrypted gecko work-bookmark secret. Requires
            programs.firefoxpwa.extended.enable.

            One-way. Setting this back to false stops managing the site but does
            not uninstall it. Removing the site is a manual
            `firefoxpwa site uninstall`, which deletes the PWA profile and the
            launcher entry but none of this module's own records: the
            dmail-applied-url, dmail-applied-origin, dmail-applied-ulid and
            dmail-installing files under `''${xdg.dataHome}/firefoxpwa` have to
            be deleted separately, and a leftover dmail-applied-ulid makes the
            next site to carry this name refused rather than adopted. Not
            automated, because an automatic uninstall would destroy the PWA
            profile and its session state.

            Rotating the secret to a URL on a different origin is also not
            applied automatically. The manifest scope is fixed at install time
            and `firefoxpwa site update` cannot rewrite it, so the installer
            refuses the rotation and the user service fails on every switch and
            login until the site is removed with `firefoxpwa site uninstall`.
            Rotations within the same origin are applied in place.

            A secret whose URL embeds credentials (`https://user:pass@host/...`)
            is refused outright, before any site lookup, because the manifest
            scope derived from it drops the userinfo and could then never contain
            the start URL. `firefoxpwa site uninstall` does not clear that one:
            the secret itself has to be stored without the credentials.
          '';
        };

        m365 = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Install the Microsoft 365 web apps listed in
              `programs.firefoxpwa.m365.apps` as Progressive Web Apps through
              firefoxpwa. Requires programs.firefoxpwa.extended.enable.

              One-way, on the same terms as
              `programs.firefoxpwa.dmail.enable`: setting this back to false, or
              dropping an entry from the list, stops managing those sites but
              does not uninstall them, and `firefoxpwa site uninstall` clears
              neither the `m365-<key>-applied-url`,
              `m365-<key>-applied-origin`, `m365-<key>-applied-ulid` nor
              `m365-<key>-installing` records under
              `''${xdg.dataHome}/firefoxpwa`. A leftover
              `m365-<key>-applied-ulid` makes the next site to carry that entry's
              name refused rather than adopted.

              Changing an entry's `url` within its installed origin is applied in
              place. Moving it to another origin is not: the manifest scope is
              fixed at install time and `firefoxpwa site update` cannot rewrite
              it, so the installer refuses that entry, and the user service
              reports failure on every switch and login until the site is removed
              with `firefoxpwa site uninstall`. The remaining entries are still
              installed, so one refusal does not hold up the rest of the suite.
            '';
          };

          apps = lib.mkOption {
            type = lib.types.listOf (
              lib.types.submodule {
                options = {
                  key = lib.mkOption {
                    type = lib.types.strMatching "[a-z0-9][a-z0-9-]*";
                    description = ''
                      Slug for this entry's install records under the firefoxpwa
                      data directory. Constrained to a path-safe alphabet because
                      it is interpolated into those file names.
                    '';
                  };
                  name = lib.mkOption {
                    type = lib.types.str;
                    description = ''
                      Launcher name. Also the idempotency key: firefoxpwa stores
                      it at `.sites.<ulid>.config.name`, which is how the
                      installer finds an entry it already installed.
                    '';
                  };
                  url = lib.mkOption {
                    type = lib.types.str;
                    description = ''
                      Start URL. The installed manifest scope is its origin, so
                      same-origin navigation stays inside the app and anything
                      else opens in the default browser.
                    '';
                  };
                };
              }
            );
            default = import ./_m365-apps.nix;
            example = lib.literalExpression ''
              [
                {
                  key = "excel";
                  name = "Excel";
                  url = "https://excel.cloud.microsoft/";
                }
              ]
            '';
            description = ''
              Microsoft 365 web apps to install. Defaults to the suite in
              `modules/browsers/firefoxpwa/_m365-apps.nix`.
            '';
          };
        };
      };

      config = lib.mkMerge [
        (lib.mkIf cfg.enable {
          # The connector is launched via the native-messaging manifest's absolute
          # path, but the `firefoxpwa` CLI must also be on PATH so the management
          # extension can detect it and so sites install/launch from a shell.
          environment.systemPackages = [ cfg.package ];
        })

        (lib.mkIf m365Cfg.enable {
          # Both collisions are silent at install time and only surface as a
          # site the installer then refuses to adopt: two entries sharing a
          # name race for the same idempotency key, and two sharing a key
          # overwrite each other's install records.
          assertions = [
            {
              assertion = duplicates m365Keys == [ ];
              message = "programs.firefoxpwa.m365.apps has duplicate keys: ${lib.concatStringsSep ", " (duplicates m365Keys)}";
            }
            {
              assertion = duplicates m365Names == [ ];
              message = "programs.firefoxpwa.m365.apps has duplicate names: ${lib.concatStringsSep ", " (duplicates m365Names)}";
            }
          ];
        })
      ];
    };
in
{
  flake.nixosModules.browsers.firefoxpwa = FirefoxpwaModule;
}

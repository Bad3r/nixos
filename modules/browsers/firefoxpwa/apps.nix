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
      dmailCfg = config.programs.firefoxpwa.dmail;
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

        # Every site installer shares one config.json and looks a site up by
        # its launcher name (.sites.<ulid>.config.name), so two claiming the
        # same name collide there rather than at eval: the second finds a site
        # no record of its own accounts for and refuses it on every run, with a
        # remedy that destroys the first one's PWA profile. Each site registers
        # the names it claims here and the assertion below is one check over all
        # of them, so a site added later joins it by contributing rather than by
        # anyone remembering to widen a comparison.
        siteNames = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          internal = true;
          description = "Launcher names claimed by the enabled firefoxpwa site installers.";
        };

        # Per-site install toggles are declared here (NixOS scope) so the common
        # app catalog and per-host apps-enable files can layer them like any other
        # app, and the Home Manager installer in ./dmail.nix can read them through
        # `osConfig`.
        dmail.name = lib.mkOption {
          type = lib.types.str;
          default = "DMail";
          description = ''
            Launcher name for the DMail site, and its idempotency key: the
            installer finds the site it installed by matching this against
            `.sites.<ulid>.config.name`. Declared rather than fixed in
            ./dmail.nix so it takes part in the collision check above.

            Editing it is not a rename. The installer no longer finds the site
            it installed under the old name, so it refuses the entry until that
            site is removed with `firefoxpwa site uninstall`, which destroys its
            PWA profile and session state.
          '';
        };

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
              it, so the installer refuses that entry until the site is removed
              with `firefoxpwa site uninstall`. The installer logs the refusal
              and exits `EX_CONFIG` (78), which the user service treats as a
              successful, non-restarting exit: the unit stays active rather than
              failing and does not trigger automatic retries. The unit still
              counts each start, including corrective switches, within its
              bounded five-start window, so the refusal remains visible while
              leaving room to fix the entry without an immediate rate-limit
              lockout. The remaining entries are still installed, so one
              refusal does not hold up the rest of the suite.

              Renaming an entry while keeping its `key` is refused on the same
              terms. `name` is the idempotency key, so the installer would
              otherwise register a second site under the new name and overwrite
              the record naming the first, leaving the original app and its
              launcher entry with nothing pointing at them.

              Editing `key` and `name` together is not refused. Both lookups then
              miss the old site, so the installer treats the entry as new and
              registers a second site while leaving the original app and its
              launcher entry orphaned. Uninstall the old site before changing
              both fields. Editing only one field while the old site remains is
              refused.
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

                      Editing it is not a rename. The records move with the slug,
                      so the installer finds the installed site with nothing
                      recording the origin it was installed at, and refuses that
                      entry until the site is removed with
                      `firefoxpwa site uninstall`, which destroys its PWA profile
                      and session state. The `m365-<old-key>-*` records are left
                      behind and have to be deleted by hand.

                      That refusal holds only while `name` is unchanged. Editing
                      both fields makes every lookup miss the installed site, so
                      it is registered a second time and the original app and
                      its launcher entry are orphaned with no message. Uninstall
                      the old site before changing both.
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
                    # Constrained to a scheme the installer can parse an origin
                    # from, and to an authority without userinfo: both are
                    # otherwise accepted here and surface only as a refusal in a
                    # user unit's journal after a switch. Unlike the DMail URL,
                    # which is a rotating secret nothing can check at eval, these
                    # are static strings. `@` is excluded from the authority
                    # only, so a path or query may still carry one.
                    type = lib.types.strMatching "https?://[^[:space:]/?#@]+([/?#][^[:space:]]*)?";
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

        (lib.mkIf dmailCfg.enable { programs.firefoxpwa.siteNames = [ dmailCfg.name ]; })

        (lib.mkIf m365Cfg.enable {
          programs.firefoxpwa.siteNames = m365Names;

          # Silent at install time and surfacing only as a site the installer
          # then refuses to adopt: two entries sharing a key overwrite each
          # other's install records. Names are checked across every site
          # installer instead, below.
          assertions = [
            {
              assertion = duplicates m365Keys == [ ];
              message = "programs.firefoxpwa.m365.apps has duplicate keys: ${lib.concatStringsSep ", " (duplicates m365Keys)}";
            }
          ];
        })

        {
          assertions = [
            {
              assertion = duplicates config.programs.firefoxpwa.siteNames == [ ];
              message = "firefoxpwa site installers claim the same launcher name, which they would fight over in one config.json: ${lib.concatStringsSep ", " (duplicates config.programs.firefoxpwa.siteNames)}";
            }
          ];
        }
      ];
    };
in
{
  flake.nixosModules.browsers.firefoxpwa = FirefoxpwaModule;
}

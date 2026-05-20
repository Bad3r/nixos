/*
  Package: zap
  Description: OWASP Zed Attack Proxy for manual and automated web application security testing.
  Homepage: https://www.zaproxy.org/
  Documentation: https://www.zaproxy.org/docs/
  Repository: https://github.com/zaproxy/zaproxy

  Summary:
    * Provides an intercepting proxy, active scanner, passive scanner, and scripting environment for web application testing.
    * Supports both desktop-driven workflows and headless API automation for CI or repeatable assessment pipelines.

  Options:
    zap: Launch the desktop proxy and scanning interface.
    -daemon: Start ZAP headlessly for API-driven automation or proxied testing.
    -addoninstall <id>: Install an add-on from the ZAP marketplace into the current profile.

  Notes:
    * Declarative add-ons are pinned in Nix and copied into the installation plugin directory.
    * Add-on dependencies must be declared explicitly; this module does not resolve Marketplace metadata.
*/
_:
let
  ZapModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.zap.extended;
      addOnFileNamePattern = "[A-Za-z0-9._+-]+\\.zap";
      addOnFileName = id: addOn: if addOn.file != null then addOn.file else "${id}.zap";
      fetchedAddOns = lib.mapAttrsToList (
        id: addOn:
        let
          fileName = addOnFileName id addOn;
        in
        {
          inherit fileName;
          source = pkgs.fetchurl {
            inherit (addOn) url hash;
            name = fileName;
          };
        }
      ) cfg.addOns;
      package =
        if cfg.addOns == { } then
          cfg.package
        else
          cfg.package.overrideAttrs (oldAttrs: {
            postInstall =
              (oldAttrs.postInstall or "")
              + ''
                mkdir -p "$out/share/zap/plugin"
              ''
              + lib.concatMapStringsSep "\n" (addOn: ''
                install -Dm444 ${addOn.source} "$out/share/zap/plugin/"${lib.escapeShellArg addOn.fileName}
              '') fetchedAddOns;
          });
    in
    {
      options.programs.zap.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable zap.";
        };

        package = lib.mkPackageOption pkgs "zap" { };

        addOns = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                url = lib.mkOption {
                  type = lib.types.str;
                  description = "URL of the ZAP Marketplace .zap file to install.";
                };

                hash = lib.mkOption {
                  type = lib.types.str;
                  description = "Hash for the add-on download, in a format accepted by fetchurl.";
                };

                file = lib.mkOption {
                  type = lib.types.nullOr (lib.types.strMatching addOnFileNamePattern);
                  default = null;
                  description = "File name to use in the ZAP plugin directory. Defaults to the attribute name with a .zap suffix.";
                };
              };
            }
          );
          default = { };
          example = lib.literalExpression ''
            {
              alertFilters = {
                url = "https://github.com/zaproxy/zap-extensions/releases/download/alertFilters-v26/alertFilters-release-26.zap";
                hash = "sha256-1skROqyWLDGVVifNomg6/kR8+dhMD4A8YCkYCJfBZkg=";
                file = "alertFilters-release-26.zap";
              };
            }
          '';
          description = "ZAP add-ons to fetch and expose from the installation plugin directory.";
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = cfg.addOns == { } || cfg.package ? overrideAttrs;
            message = "programs.zap.extended.addOns requires a package that supports overrideAttrs.";
          }
        ]
        ++ lib.mapAttrsToList (
          id: addOn:
          let
            fileName = addOnFileName id addOn;
          in
          {
            assertion = builtins.match addOnFileNamePattern fileName != null;
            message = "programs.zap.extended.addOns.${id} must resolve to a simple .zap file name.";
          }
        ) cfg.addOns;

        environment.systemPackages = [ package ];
      };
    };
in
{
  flake.nixosModules.apps.zap = ZapModule;
}

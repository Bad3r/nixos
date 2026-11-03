/*
  Package: warp-devices
  Description: List Cloudflare Zero Trust WARP devices with their status and addresses, and one device's DEX history.
  Homepage: https://github.com/Bad3r/nixos
  Documentation: https://github.com/Bad3r/nixos/blob/main/docs/apps/cloudflare/warp/devices.md
  Repository: https://github.com/Bad3r/nixos

  Summary:
    * Lists active WARP registrations with DEX status, Mesh and public IPs, OS, and last seen.
    * Shows one device's status, edge, and network changes from DEX raw reports.

  Options:
    list [--ipv6] [--user]: Print the device table (the default command).
    history <device> [--hours N] [--all]: Print a device's report timeline.
    --json: Print JSON instead of a table.
    --color / --no-color: Force color on or off.
*/
_:
let
  secretFileName = "cloudflare-warp.yaml";

  WarpDevicesModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.warp-devices.extended;
    in
    {
      options.programs.warp-devices.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable the warp-devices command line.";
        };

        package = lib.mkPackageOption pkgs "warp-devices" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };

  # The CLI reads $XDG_CONFIG_HOME/warp-devices/{account-id,api-token}.
  WarpDevicesHomeModule =
    {
      lib,
      metaOwner,
      osConfig,
      secretsRoot,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "warp-devices" "extended" "enable" ] false osConfig;
      secretFile = secretsRoot + "/${secretFileName}";
      secretExists = builtins.pathExists secretFile;
      configDir = "/home/${metaOwner.username}/.config/warp-devices";
      credential = file: key: {
        sopsFile = secretFile;
        format = "yaml";
        inherit key;
        path = "${configDir}/${file}";
        mode = "0400";
      };
    in
    {
      config = lib.mkMerge [
        (lib.mkIf (nixosEnabled && secretExists) {
          sops.secrets = {
            "warp-devices/account-id" = credential "account-id" "account_id";
            "warp-devices/api-token" = credential "api-token" "zero_trust_read_api_token";
          };
        })

        (lib.mkIf (nixosEnabled && !secretExists) {
          warnings = [
            "programs.warp-devices.extended.enable is true but ${toString secretFile} is missing; warp-devices has no credentials."
          ];
        })
      ];
    };
in
{
  flake.nixosModules.apps.warp-devices = WarpDevicesModule;
  flake.homeManagerModules.apps.warp-devices = WarpDevicesHomeModule;

  perSystem =
    { pkgs, ... }:
    {
      # passthru opts this check into the runtime step of .github/workflows/check.yml, which
      # builds it and so runs the package's unit tests; nothing else in CI builds an
      # overlay-only package.
      checks."apps/warp-devices" =
        pkgs.runCommand "warp-devices-check"
          {
            passthru.runtimeCheck = true;
            package = pkgs.callPackage ../../packages/warp-devices { };
          }
          ''
            test -x "$package/bin/warp-devices"
            touch "$out"
          '';
    };
}

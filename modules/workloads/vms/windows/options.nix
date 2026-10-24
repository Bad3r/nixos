_:
let
  windowsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (lib) types;
      inherit (config.workloads) guests;
      mkSeed = import ./_seed.nix { inherit lib pkgs; };
      windowsGuests = lib.filterAttrs (
        _: guest: guest.kind == "windows" && guest.ensure == "present"
      ) guests;

      serviceModule = {
        options = {
          port = lib.mkOption {
            type = types.port;
            description = "Guest port the rule opens.";
          };

          protocol = lib.mkOption {
            type = types.enum [
              "tcp"
              "udp"
            ];
            default = "tcp";
            description = "Transport protocol of the port.";
          };
        };
      };

      guestModule =
        { name, config, ... }:
        let
          inherit (config) windows;
        in
        {
          options.windows = {
            edition = lib.mkOption {
              type = types.str;
              default = "Windows 11 Pro";
              description = "Name of the image in the installation media's `install.wim` that Setup installs.";
            };

            locale = lib.mkOption {
              type = types.str;
              default = "en-US";
              description = "Language and locale tag for Setup, the system, and the account.";
            };

            timeZone = lib.mkOption {
              type = types.str;
              default = "UTC";
              description = "Windows time zone ID, such as `Arab Standard Time`.";
            };

            account = {
              name = lib.mkOption {
                type = types.strMatching "[A-Za-z0-9._-]{1,20}";
                description = ''
                  Local administrator that Setup creates with a blank password
                  and logs on once; provisioning then sets its password.
                '';
              };

              passwordSecret = lib.mkOption {
                type = types.str;
                default = "workloads/${name}/password";
                defaultText = lib.literalExpression ''"workloads/<name>/password"'';
                description = "`sops.secrets` entry holding the account password.";
              };

              authorizedKeys = lib.mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "SSH public keys that OpenSSH accepts for administrators.";
              };
            };

            productKeySecret = lib.mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                `sops.secrets` entry holding a Windows product key, which
                provisioning installs and activates. Without one, or while its
                file is absent, Windows stays unactivated.
              '';
            };

            services = lib.mkOption {
              type = types.attrsOf (types.submodule serviceModule);
              default = { };
              description = ''
                Inbound ports the guest firewall opens to the gateway of each of
                the guest's networks, as rules named `workloads-<name>`.
                Provisioning removes `workloads-*` rules nothing declares.
              '';
            };

            seedIso = lib.mkOption {
              type = types.package;
              readOnly = true;
              default = mkSeed {
                guestName = name;
                accountName = windows.account.name;
                inherit (windows) edition locale timeZone;
              };
              defaultText = lib.literalMD "the seed CD-ROM rendered from these options";
              description = "Seed CD-ROM with the answer file, drivers, guest tools, and installers, attached as the `<name>-seed` image while `install.media` is not empty.";
            };

          };

          # Setup reads the answer file from any CD-ROM.
          config.install.images = lib.mkIf (config.kind == "windows" && config.install.media != [ ]) [
            "${name}-seed"
          ];
        };

      guestAssertions =
        name: guest:
        let
          check = assertion: message: {
            inherit assertion;
            message = "workloads.guests.${name}: ${message}";
          };
          inherit (guest.windows) productKeySecret;
        in
        [
          (check (lib.stringLength name <= 15) "Windows computer names have at most 15 characters")
          (check guest.guestAgent "Windows guests are provisioned through guestAgent")
          (check (guest.interfaces != { }) "Windows guests need an interface for SSH and Remote Desktop")
          (check (
            config.sops.secrets ? ${guest.windows.account.passwordSecret}
          ) "windows.account.passwordSecret names no sops.secrets entry")
          (check (
            productKeySecret == null || config.sops.secrets ? ${productKeySecret}
          ) "windows.productKeySecret names no sops.secrets entry")
        ];
    in
    {
      options.workloads.guests = lib.mkOption {
        type = types.attrsOf (types.submodule guestModule);
      };

      config = lib.mkIf (windowsGuests != { }) {
        assertions = lib.concatLists (lib.mapAttrsToList guestAssertions windowsGuests);

        workloads.images = lib.mapAttrs' (
          name: guest: lib.nameValuePair "${name}-seed" { expected = "${guest.windows.seedIso}"; }
        ) windowsGuests;
      };
    };
in
{
  flake.nixosModules."workloads-vms" = windowsModule;
}

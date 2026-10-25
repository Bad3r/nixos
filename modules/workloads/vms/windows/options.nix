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

      shareModule = {
        options.driveLetter = lib.mkOption {
          type = types.nullOr (types.strMatching "[G-Z]");
          default = null;
          description = ''
            Drive letter a Windows guest mounts the share at; D to F stay
            free for the installation CD-ROMs. Shares without one take the
            highest letters no other share pins, from Z down in tag order.
            Other guest kinds ignore it.
          '';
        };
      };

      # Highest letters first, away from the ones Windows gives disks and CD-ROMs.
      freeLetters = lib.reverseList (lib.stringToCharacters "GHIJKLMNOPQRSTUVWXYZ");

      driveLetters =
        shares:
        let
          enabled = lib.filterAttrs (_: share: share.enable) shares;
          pinned = lib.filterAttrs (_: share: share.driveLetter != null) enabled;
          taken = lib.mapAttrsToList (_: share: share.driveLetter) pinned;
          free = lib.filter (letter: !lib.elem letter taken) freeLetters;
          unpinned = lib.attrNames (removeAttrs enabled (lib.attrNames pinned));
        in
        lib.mapAttrs (_: share: share.driveLetter) pinned
        // lib.listToAttrs (lib.zipListsWith lib.nameValuePair unpinned free);

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
          options.shares = lib.mkOption {
            type = types.attrsOf (types.submodule shareModule);
          };

          options.windows = {
            edition = lib.mkOption {
              type = types.str;
              default = "Windows 11 Enterprise";
              description = "Name of an image in the installation media's `install.wim` that Setup installs, such as `Windows 11 Enterprise LTSC 2024` from LTSC media; without a product key, only volume license media install unattended.";
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

              autoLogon = lib.mkOption {
                type = types.bool;
                default = true;
                description = ''
                  Whether the guest signs the account on at boot, with the
                  password in an LSA secret, as the SPICE clipboard cannot
                  reach the sign-in screen.
                '';
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
                file is absent, provisioning leaves activation as it is.
              '';
            };

            office.installer = lib.mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                `workloads.media` entry holding a Click-to-Run Office installer,
                such as the `OfficeSetup.exe` a Microsoft account offers.
                Provisioning copies it into a guest that lists no Office suite
                and runs it; the installer downloads Office itself, and signing
                in to an Office app licenses it.
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

            virtiofs = {
              mode = lib.mkOption {
                type = types.enum [
                  "launcher"
                  "service"
                ];
                default = "launcher";
                description = ''
                  How the guest mounts its shares, all of which virtio-win
                  calls a Tech Preview on Windows. `launcher` starts one WinFsp
                  launcher instance per share from a startup task; `service`
                  runs the single `VirtioFsSvc` service for one share attached
                  at boot.
                '';
              };

              driveLetters = lib.mkOption {
                type = types.attrsOf types.str;
                readOnly = true;
                default = driveLetters config.shares;
                defaultText = lib.literalMD "each enabled share's `driveLetter`, or the letter assigned to it";
                description = "Drive letter of each enabled share, keyed by tag.";
              };
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
          inherit (guest.windows) office productKeySecret;
          shares = lib.filterAttrs (_: share: share.enable) guest.shares;
          pinned = lib.filter (letter: letter != null) (
            lib.mapAttrsToList (_: share: share.driveLetter) shares
          );
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
          (check (
            office.installer == null || config.workloads.media ? ${office.installer}
          ) "windows.office.installer names no workloads.media entry")
          (check (lib.allUnique pinned) "shares: two shares take the same driveLetter")
          (check (lib.length (lib.attrNames shares) <= 20)
            "shares: a Windows guest mounts at most 20 shares, on G to Z, a drop included unless shares.drop.enable = false"
          )
          (check
            (
              guest.windows.virtiofs.mode != "service"
              || (
                lib.length (lib.attrNames shares) <= 1 && lib.all (share: !share.runtime) (lib.attrValues shares)
              )
            )
            "windows.virtiofs.mode = \"service\" mounts one share, attached at boot, a drop included unless shares.drop.enable = false"
          )
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
        ) (lib.filterAttrs (_: guest: guest.install.media != [ ]) windowsGuests);
      };
    };
in
{
  flake.nixosModules."workloads-vms" = windowsModule;
}

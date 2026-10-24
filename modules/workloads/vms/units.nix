_:
let
  unitsModule =
    {
      config,
      lib,
      pkgs,
      metaOwner,
      ...
    }:
    let
      libvirtCfg = config.programs.libvirt.extended;
      networks = lib.filterAttrs (_: network: network.libvirt.enable) config.workloads.networks;
      inherit (config.workloads) guests images media;
      presentGuests = lib.filterAttrs (_: guest: guest.ensure == "present") guests;
      owner = metaOwner.username;

      stateDir = "/var/lib/workloads";
      mediaDir = "${stateDir}/media";

      renderNetwork = import ./_render-network.nix { inherit lib; };
      renderDomain = import ./_render-domain.nix { inherit lib mediaDir; };

      validatedXml =
        kind: name: text:
        pkgs.writeTextFile {
          name = "workloads-${kind}-${name}.xml";
          inherit text;
          checkPhase = ''
            ${libvirtCfg.package}/bin/virt-xml-validate "$target" ${kind}
          '';
        };

      # DHCP reservations of every present guest interface on a network.
      dhcpHosts =
        networkName:
        lib.concatLists (
          lib.mapAttrsToList (
            guestName: guest:
            lib.mapAttrsToList (nic: _: {
              mac = guest.mac.${nic};
              name = guestName;
              ip = guest.address.${nic};
            }) (lib.filterAttrs (_: interface: interface.network == networkName) guest.interfaces)
          ) presentGuests
        );

      networkXml =
        name: network: validatedXml "network" name (renderNetwork name network (dhcpHosts name));

      python = pkgs.python3.withPackages (ps: [ ps.libvirt ]);
      reconcile = "${python.interpreter} -I ${./_reconciler.py}";

      guestSpec =
        name: guest:
        pkgs.writeText "workloads-guest-${name}.json" (
          builtins.toJSON (
            {
              inherit name;
              inherit (guest) uuid ensure stateDir;
            }
            // lib.optionalAttrs (guest.ensure == "present") {
              inherit (guest) autostart;
              xml = validatedXml "domain" name (renderDomain guest);
              nvram = guest.nvramPath;
              disks = lib.mapAttrsToList (disk: spec: {
                path = "${guest.stateDir}/${disk}.qcow2";
                inherit (spec) size;
                seed = if spec.seed == null then null else { inherit (images.${spec.seed}) path expected; };
              }) guest.disks;
            }
          )
        );

      declaredManifest = pkgs.writeText "workloads-declared.json" (
        builtins.toJSON {
          networks = lib.mapAttrsToList (_: network: network.libvirt.uuid) networks;
          guests = lib.mapAttrsToList (_: guest: guest.uuid) guests;
        }
      );

      mediaManifest = pkgs.writeText "workloads-media.json" (
        builtins.toJSON (lib.mapAttrs (_: entry: { inherit (entry) source sha256; }) media)
      );

      directory = mode: user: group: {
        d = { inherit mode user group; };
      };

      guestUnit =
        name: guest:
        let
          prerequisites =
            lib.unique (
              map (interface: "workloads-vm-net-${interface.network}.service") (lib.attrValues guest.interfaces)
            )
            ++ lib.optional (guest.install.media != [ ]) "workloads-vm-media.service";
        in
        {
          name = "workloads-vm-guest-${name}";
          value = {
            description = "Define the ${name} workload guest in libvirt";
            wantedBy = [ "multi-user.target" ];
            requires = [ "libvirtd.service" ];
            wants = prerequisites;
            after = [ "libvirtd.service" ] ++ prerequisites;
            path = [ libvirtCfg.qemuPackage ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = "${reconcile} guest ${guestSpec name guest}";
            };
          };
        };

      guestAssertions =
        name: guest:
        let
          prefix = "workloads.guests.${name}";
          check = assertion: message: {
            inherit assertion;
            message = "${prefix}: ${message}";
          };
          inherit (guest) firmware;
        in
        [
          (check (builtins.match "[a-z0-9][a-z0-9-]*" name != null) "names must match [a-z0-9][a-z0-9-]*")
        ]
        ++ lib.optionals (guest.ensure == "present") (
          [
            (check (
              guest.kind != "windows" || (firmware.secureBoot && firmware.enrolledKeys && firmware.tpm)
            ) "windows guests need firmware.secureBoot, firmware.enrolledKeys, and firmware.tpm")
            (check (
              !firmware.enrolledKeys || firmware.secureBoot
            ) "firmware.enrolledKeys needs firmware.secureBoot")
            (check (
              guest.trust == "trusted" || !(guest.clipboard || guest.fileTransfer)
            ) "untrusted guests share no clipboard or files")
            (check (
              !guest.usbRedirection || guest.display == "spice"
            ) "usbRedirection needs display = \"spice\"")
            (check (
              guest.trust == "trusted" || lib.all (share: !share.enable) (lib.attrValues guest.shares)
            ) "untrusted guests get no shares")
          ]
          ++ lib.mapAttrsToList (
            tag: _:
            # QEMU refuses a virtiofs tag longer than 36 bytes when the guest starts.
            check (
              builtins.match "[a-z0-9][a-z0-9-]{0,35}" tag != null
            ) "shares.${tag}: tags must match [a-z0-9][a-z0-9-]* and have at most 36 characters"
          ) guest.shares
          ++ lib.mapAttrsToList (
            disk: spec:
            check (
              builtins.match "[a-z0-9][a-z0-9-]*" disk != null && (spec.seed == null || images ? ${spec.seed})
            ) "disks.${disk}: names must match [a-z0-9][a-z0-9-]* and a seed must name a workloads.images entry"
          ) guest.disks
          ++ map (
            item: check (media ? ${item}) "install.media names ${item}, which workloads.media does not declare"
          ) guest.install.media
          ++ [
            # Two reservations under one guest name make libvirt refuse the second.
            (check (lib.allUnique (
              lib.mapAttrsToList (_: interface: interface.network) guest.interfaces
            )) "interfaces: at most one interface per network")
          ]
          ++ lib.mapAttrsToList (
            nic: interface:
            let
              network = networks.${interface.network} or null;
              offset = interface.hostOffset;
            in
            check
              (network != null && (offset < network.libvirt.dhcp.start || offset > network.libvirt.dhcp.end))
              "interfaces.${nic}: the network needs libvirt.enable and the offset must lie outside its DHCP range"
          ) guest.interfaces
        );

      # Interfaces sharing a reservation would compete for one address.
      offsetsUnique =
        let
          offsets = lib.concatLists (
            lib.mapAttrsToList (
              _: guest:
              map (interface: "${interface.network}/${toString interface.hostOffset}") (
                lib.attrValues guest.interfaces
              )
            ) presentGuests
          );
        in
        {
          assertion = lib.allUnique offsets;
          message = "workloads.guests: two interfaces reserve one address: ${lib.concatStringsSep ", " offsets}";
        };

      networkUnit = name: network: {
        name = "workloads-vm-net-${name}";
        value = {
          description = "Define the ${name} workload network in libvirt";
          wantedBy = [ "multi-user.target" ];
          # Without the egress rules, bridge traffic would route through the main table.
          requires = [
            "libvirtd.service"
            "workload-egress.service"
          ];
          after = [
            "libvirtd.service"
            "workload-egress.service"
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${reconcile} network ${networkXml name network}${lib.optionalString network.libvirt.autostart " --autostart"}";
          };
        };
      };
    in
    {
      config = lib.mkMerge [
        {
          programs.libvirt.extended.enable = lib.mkIf (networks != { } || media != { } || guests != { }) (
            lib.mkOverride 1050 true
          );

          assertions =
            # Names become file names in the media directory.
            lib.mapAttrsToList (name: _: {
              assertion = builtins.match "[a-z0-9][a-z0-9._-]*" name != null;
              message = "workloads.media.${name}: names must match [a-z0-9][a-z0-9._-]*";
            }) media
            ++ lib.concatLists (lib.mapAttrsToList guestAssertions guests)
            ++ [
              # A copied UUID shares disks, NVRAM, and TPM state between guests.
              {
                assertion = lib.allUnique (lib.mapAttrsToList (_: guest: guest.uuid) guests);
                message = "workloads.guests: UUIDs must be unique";
              }
              offsetsUnique
            ];
        }

        (lib.mkIf libvirtCfg.enable {
          virtualisation.spiceUSBRedirection.enable = lib.mkIf (lib.any (guest: guest.usbRedirection) (
            lib.attrValues presentGuests
          )) true;

          virtualisation.libvirtd.allowedBridges = map (network: network.bridge) (
            lib.filter (network: network.libvirt.sessionAttach) (lib.attrValues networks)
          );

          systemd.tmpfiles.settings.workloads-vms = {
            ${stateDir} = directory "0755" "root" "root";
            "${stateDir}/guests" = directory "0755" "root" "root";
            ${mediaDir} = directory "0755" "root" "root";
            # The owner's `nix build --out-link` targets for guest images.
            "${stateDir}/images" = directory "0755" owner config.users.users.${owner}.group;
            "${stateDir}/golden" = directory "0700" "root" "root";
          };

          systemd.services =
            lib.listToAttrs (lib.mapAttrsToList networkUnit networks ++ lib.mapAttrsToList guestUnit guests)
            // {
              workloads-vm-orphans = {
                description = "Warn about owned workload objects that nothing declares";
                wantedBy = [ "multi-user.target" ];
                requires = [ "libvirtd.service" ];
                after = [
                  "libvirtd.service"
                ]
                ++ lib.mapAttrsToList (name: _: "workloads-vm-net-${name}.service") networks
                ++ lib.mapAttrsToList (name: _: "workloads-vm-guest-${name}.service") guests;
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                  ExecStart = "${reconcile} orphans ${declaredManifest}";
                };
              };

              workloads-vm-media = {
                description = "Stage declared workload media";
                wantedBy = [ "multi-user.target" ];
                # Fails while a source volume is absent instead of staging nothing.
                unitConfig.RequiresMountsFor = lib.unique (map (entry: dirOf entry.source) (lib.attrValues media));
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                  ExecStart = "${reconcile} media ${mediaManifest} ${mediaDir} --owner ${owner}";
                };
              };
            };
        })
      ];
    };
in
{
  flake.nixosModules."workloads-vms" = unitsModule;
}

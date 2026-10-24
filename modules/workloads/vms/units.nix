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
      inherit (config.workloads) media;
      owner = metaOwner.username;

      stateDir = "/var/lib/workloads";
      mediaDir = "${stateDir}/media";

      renderNetwork = import ./_render-network.nix { inherit lib; };
      networkXml =
        name: network:
        pkgs.writeTextFile {
          name = "workloads-network-${name}.xml";
          text = renderNetwork name network;
          checkPhase = ''
            ${libvirtCfg.package}/bin/virt-xml-validate "$target" network
          '';
        };

      python = pkgs.python3.withPackages (ps: [ ps.libvirt ]);
      reconcile = "${python.interpreter} ${./_reconciler.py}";

      mediaManifest = pkgs.writeText "workloads-media.json" (
        builtins.toJSON (lib.mapAttrs (_: entry: { inherit (entry) source sha256; }) media)
      );

      directory = mode: user: group: {
        d = { inherit mode user group; };
      };

      networkUnit = name: network: {
        name = "workloads-vm-net-${name}";
        value = {
          description = "Define the ${name} workload network in libvirt";
          wantedBy = [ "multi-user.target" ];
          requires = [ "libvirtd.service" ];
          after = [ "libvirtd.service" ];
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
          programs.libvirt.extended.enable = lib.mkIf (networks != { } || media != { }) (
            lib.mkOverride 1050 true
          );
        }

        (lib.mkIf libvirtCfg.enable {
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

          systemd.services = lib.listToAttrs (lib.mapAttrsToList networkUnit networks) // {
            workloads-vm-media = {
              description = "Stage declared workload media";
              wantedBy = [ "multi-user.target" ];
              # Fails while a source volume is absent instead of staging nothing.
              unitConfig.RequiresMountsFor = lib.unique (map (entry: dirOf entry.source) (lib.attrValues media));
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = "${reconcile} media ${mediaManifest} ${mediaDir}";
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

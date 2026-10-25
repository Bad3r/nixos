/*
  Package: sbx
  Description: Disposable agent sandboxes: TTL-bound VMs on the owner's qemu:///session.
  Homepage: https://github.com/Bad3r/nixos
  Documentation: https://github.com/Bad3r/nixos/tree/main/docs/apps/sbx

  Summary:
    * Boots throwaway VMs from Nix-built bases for unknown binaries, untrusted repositories, and GUI checks.
    * Accepts no domain XML, host disk path, or resource value above the configured ceilings.

  Options:
    create <base>: Start a sandbox and print its name, vsock CID, and address.
    --net egress: Attach the sandbox to the sbx workload network instead of leaving it without a NIC.
    run <base> -- CMD: Create, copy in, run, copy out, and destroy in one call.
    exec <name> -- CMD: Run a command over SSH on vsock.
    --json: Print results and errors as JSON.

  Notes:
    * Sandboxes are untrusted guests: no vdagent channel, no shared folders, and no network unless
      --net egress puts them on the isolated sbx workload network.
    * QEMU runs inside sbx.slice through the sbx-libvirt user unit, so the slice bounds every sandbox together.
    * Each QEMU runs in its own local vsock namespace, so a guest never reaches a host vsock listener.
    * Bases build on demand from this flake and never enter the host closure.
*/
{ config, ... }:
let
  hostsRegistry = config.flake.lib.nixos.hosts or { };

  SbxModule =
    {
      config,
      lib,
      pkgs,
      hostName,
      metaOwner,
      ...
    }:
    let
      inherit (lib) types;
      cfg = config.programs.sbx.extended;
      libvirtCfg = config.programs.libvirt.extended;
      egressNetwork = config.workloads.networks.sbx or null;
      gib = 1024 * 1024 * 1024;
      positive =
        description:
        lib.mkOption {
          type = types.ints.positive;
          inherit description;
        };
    in
    {
      options.programs.sbx.extended = {
        enable = lib.mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable sbx agent sandboxes.";
        };

        package = lib.mkPackageOption pkgs "sbx" { };

        finalPackage = lib.mkOption {
          type = types.package;
          readOnly = true;
          description = "sbx with the settings below and the libvirt app's QEMU.";
        };

        limits = lib.mkOption {
          type = types.submodule {
            options = {
              running = positive "Sandboxes that may run at once.";
              memory = positive "GiB of declared memory across running sandboxes.";
              sliceMemory = positive "MemoryMax in GiB of sbx.slice, which also holds QEMU's own overhead.";
              cpus = lib.mkOption {
                type = types.str;
                description = "Host CPUs that sandbox vCPUs and emulator threads are pinned to.";
              };
              ttl = positive "Default sandbox lifetime in hours, host sleep included.";
              maxTtl = positive "Longest lifetime in hours a sandbox may request.";
              disk = positive "GiB the sandbox state directory may use before create refuses.";
              minFree = positive "GiB that must stay free on the state directory's filesystem.";
            };
          };
          default =
            hostsRegistry.${hostName}.sbx
              or (throw "programs.sbx.extended: add sbx limits to modules/hosts/${hostName}/policy.nix");
          defaultText = lib.literalExpression "flake.lib.nixos.hosts.<host>.sbx";
          description = "Host ceilings for all sandboxes together.";
        };

        sandbox = {
          memory = lib.mkOption {
            type = types.ints.positive;
            default = 2048;
            description = "Default MiB per sandbox.";
          };
          maxMemory = lib.mkOption {
            type = types.ints.positive;
            default = 6144;
            description = "Most MiB one sandbox may request.";
          };
          cpus = lib.mkOption {
            type = types.ints.positive;
            default = 2;
            description = "Default vCPUs per sandbox.";
          };
          maxCpus = lib.mkOption {
            type = types.ints.positive;
            default = 8;
            description = "Most vCPUs one sandbox may request.";
          };
          disk = lib.mkOption {
            type = types.ints.positive;
            default = 8;
            description = "Virtual GiB of a sandbox disk; create reserves it against the disk cap for every running sandbox.";
          };
        };

        flake = lib.mkOption {
          type = types.str;
          default = "${config.users.users.${metaOwner.username}.home}/nixos";
          defaultText = lib.literalExpression ''"''${home}/nixos"'';
          description = "Flake that `sbx base build` builds bases from.";
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = cfg.limits.ttl <= cfg.limits.maxTtl;
            message = "programs.sbx.extended.limits.ttl exceeds limits.maxTtl";
          }
          {
            assertion = cfg.sandbox.memory <= cfg.sandbox.maxMemory && cfg.sandbox.cpus <= cfg.sandbox.maxCpus;
            message = "programs.sbx.extended.sandbox: a default exceeds its maximum";
          }
          {
            assertion = cfg.sandbox.maxMemory <= cfg.limits.memory * 1024;
            message = "programs.sbx.extended.sandbox.maxMemory (MiB) exceeds limits.memory (GiB)";
          }
          {
            assertion = cfg.limits.memory < cfg.limits.sliceMemory;
            message = "programs.sbx.extended.limits.memory must stay below sliceMemory, which also holds QEMU overhead";
          }
        ];

        programs.sbx.extended.finalPackage = cfg.package.override {
          qemu_kvm = libvirtCfg.qemuPackage;
          nix = config.nix.package;
          settings = {
            limits = {
              inherit (cfg.limits) running;
              memoryMiB = cfg.limits.memory * 1024;
              sandboxMemoryMiB = cfg.sandbox.maxMemory;
              sandboxCpus = cfg.sandbox.maxCpus;
              ttlSeconds = cfg.limits.maxTtl * 3600;
              diskBytes = cfg.limits.disk * gib;
              minFreeBytes = cfg.limits.minFree * gib;
            };
            defaults = {
              memoryMiB = cfg.sandbox.memory;
              inherit (cfg.sandbox) cpus;
              ttlSeconds = cfg.limits.ttl * 3600;
              diskGiB = cfg.sandbox.disk;
            };
            inherit (cfg) flake;
            cpuset = cfg.limits.cpus;
            # An object, or why `--net egress` is unavailable.
            egress =
              if egressNetwork == null then
                "this host declares no workloads.networks.sbx"
              else if !(egressNetwork.libvirt.enable && egressNetwork.libvirt.sessionAttach) then
                "workloads.networks.sbx needs libvirt.enable and libvirt.sessionAttach"
              else
                {
                  inherit (egressNetwork) bridge;
                  # libvirt writes it world-readable, so sbx reads leases without a system connection.
                  leases = "/var/lib/libvirt/dnsmasq/${egressNetwork.bridge}.status";
                };
            unit = "sbx-libvirt.service";
            slice = "sbx.slice";
            outputLimit = 1024 * 1024;
            bootTimeout = 180;
          };
        };

        environment.systemPackages = [ cfg.finalPackage ];

        # Each sandbox's QEMU runs in a new namespace, which sbx-qemu refuses unless local.
        boot.kernel.sysctl."net.vsock.child_ns_mode" = "local";
      };
    };
in
{
  flake.nixosModules.apps.sbx = SbxModule;
}

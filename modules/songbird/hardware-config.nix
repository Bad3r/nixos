# Hardware truth for songbird (Intel Core Ultra 9 285K on an ASUS ROG Maximus
# Z890 Hero), harvested from `nixos-generate-config` and `lsblk` on the
# installed disk A rather than copied from the plan in docs/songbird/.
_: {
  configurations.nixos.songbird.module =
    {
      config,
      lib,
      pkgs,
      metaOwner,
      ...
    }:
    let
      owner = metaOwner.username;
      ownerCfg = config.users.users.${owner};
      # /shared needs a stable numeric owner. NixOS allocates a free UID for
      # null, which cannot safely be represented by this static mount option.
      ownerGroup =
        if ownerCfg.group == "" then
          throw "songbird /shared requires users.users.${owner}.group to be set"
        else
          ownerCfg.group;
      ownerUid =
        if ownerCfg.uid == null then
          throw "songbird /shared requires users.users.${owner}.uid to be pinned"
        else
          ownerCfg.uid;
      # attrByPath's default covers an absent group, not a present one whose
      # gid is null (the option default for any group outside ids.gids).
      ownerGidRaw = lib.attrByPath [ "users" "groups" ownerGroup "gid" ] null config;
      ownerGid =
        if ownerGidRaw == null then
          throw "songbird /shared requires users.groups.${ownerGroup}.gid to be pinned"
        else
          ownerGidRaw;
    in
    {
      # Platform configuration (required)
      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

      hardware = {
        cpu.intel = {
          # Arrow Lake-S microcode; nixos-hardware's common-cpu-intel-cpu-only
          # profile (hosts-common) would only derive this from
          # enableRedistributableFirmware, so pin it.
          updateMicrocode = true;
          # NPU 4 at 0000:00:0b.0 (intel_vpu): firmware plus the Level Zero
          # driver, as nixos-generate-config reports for this CPU.
          npu.enable = true;
        };

        # flake.nixosModules.bluetooth (hosts-common) enables the controller
        # (btintel over USB); this adds the kernel-side experimental features
        # system76 also carries for BLE battery reporting.
        bluetooth.settings.General.KernelExperimental = true;

        # Explicit firmware set, verified against the drivers the stock install
        # bound: iwlwifi (Intel BE200 Wi-Fi 7, iwlwifi-gl-*), btintel/btusb
        # (ibt-*), r8169 for the Realtek RTL8126 5 GbE (rtl_nic/rtl8126a-*),
        # i915 DMC/GuC/HuC for the Xe-LPG iGPU, and the SOF path the Arrow
        # Lake HDA controller can select (sof-audio-pci-intel-mtl). NVIDIA GSP
        # firmware ships with the driver package (hardware.nvidia.gsp).
        firmware = lib.mkAfter [
          pkgs.linux-firmware
          pkgs.sof-firmware
          pkgs.wireless-regdb
        ];
      };

      boot = {
        # The initrd module list from modules/hosts/common/boot.nix (xhci_pci,
        # ahci, nvme, thunderbolt, usbhid, usb_storage, sd_mod, ...) covers
        # everything nixos-generate-config reports on this board.
        initrd.luks.devices = {
          # Disk A (WD_BLACK SN8100 4TB, M.2_1, 0000:01:00.0): NixOS root.
          cryptroot = {
            device = "/dev/disk/by-uuid/655308da-05a9-4989-95d0-7ac3f24a5f57";
            allowDiscards = true;
          };
          # Disk A: 51 GiB swap, also the hibernation image (48 GB RAM).
          cryptswap = {
            device = "/dev/disk/by-uuid/d776cdd8-ab0f-4081-abc0-c0e11b1aa6da";
            allowDiscards = true;
          };
          # Samsung 860 PRO 2TB SATA: the LUKS2 + XFS /data volume.
          # Root does not depend on it, so nofail keeps an absent or unopened
          # drive from dropping the systemd initrd into the emergency shell.
          data = {
            device = "/dev/disk/by-uuid/183d1f98-e95d-4d6c-89de-cbed409bd9a0";
            allowDiscards = true;
            crypttabExtraOpts = [
              "nofail"
              "x-systemd.device-timeout=60s"
            ];
          };
        };

        # nofail above also drops Before=cryptsetup.target, so initrd-cleanup
        # isolated initrd-switch-root.target out from under this unlock while
        # its argon2id was still running and killed it. Restore the wait, but
        # bound both the absent-device and unlock-prompt paths at 60 seconds.
        # nofail emits no Requires=, so either expiry still lets root boot.
        initrd.systemd.services."systemd-cryptsetup@data" = {
          overrideStrategy = "asDropin";
          wantedBy = [ "initrd.target" ];
          before = [ "initrd.target" ];
          serviceConfig.TimeoutStartSec = "60s";
        };

        # Hibernation target: swap inside the cryptswap mapping.
        resumeDevice = "/dev/mapper/cryptswap";

        supportedFilesystems = [
          "ntfs"
          "xfs"
        ];

        # Loader skeleton comes from modules/hosts/common/boot.nix.
        loader.systemd-boot.configurationLimit = 5;
      };

      fileSystems = {
        "/" = {
          device = "/dev/mapper/cryptroot";
          fsType = "ext4";
        };
        "/boot" = {
          device = "/dev/disk/by-uuid/3028-D139";
          fsType = "vfat";
          options = [
            "fmask=0077"
            "dmask=0077"
          ];
        };

        # Encrypted XFS /data volume (via /dev/mapper/data).
        "/data" = {
          device = "/dev/mapper/data";
          fsType = "xfs";
          options = [
            "noatime"
            "nofail"
          ];
        };

        # WDC PC SN720 1TB (chipset M.2, 0000:82:00.0): plain NTFS volume
        # labeled "WD 1 TB", the drive shared with the Windows dual boot.
        # Kernel ntfs3 with windows_names blocks names Windows cannot read;
        # nofail keeps a dirty (Windows fast-startup) or absent volume from
        # blocking boot. The masks are the /boot pair above: uid=/gid= alone
        # leave the mode at ~current_umask() of whatever mounted the volume,
        # and "shared" here means shared with Windows, not with other local
        # accounts.
        "/shared" = {
          device = "/dev/disk/by-uuid/1AE668D2E668B025";
          fsType = "ntfs3";
          options = [
            "uid=${toString ownerUid}"
            "gid=${toString ownerGid}"
            "fmask=0077"
            "dmask=0077"
            "windows_names"
            "noatime"
            "nofail"
          ];
        };
      };

      swapDevices = [ { device = "/dev/mapper/cryptswap"; } ];

      # Thunderbolt 4 / USB4 device authorization for the two rear ports
      # (0000:00:0d.2).
      services.hardware.bolt.enable = true;

      # No tmpfiles rule for /data. systemd.mount(5) creates the mount point
      # itself, and tmpfiles.d(5) applies ownership "regardless of whether it is
      # created anew, or already existed" from a unit ordered After=local-fs
      # .target, which a nofail mount is not ordered before. The rule therefore
      # wrote an owner-writable /data onto the root filesystem on any boot where
      # the volume was absent, and anything writing there filled / silently.

      # Enforces operating rule 2 of docs/songbird/nixos-setup.md: /shared
      # mounted during imaging restores stale NTFS metadata, corrupting the
      # volume silently, so ExecStartPre aborts the unit on a busy /shared.
      # Collides with a shipped unit, so NixOS renders this as a drop-in
      # (asDropinIfExists) rather than a replacement. Remount runs on
      # ExecStopPost, not ExecStartPost, which nixpkgs skips on any failed
      # transition. The /run flag marks that this unit performed the unmount,
      # so remount, and the unprefixed mount command, only ever run for that
      # transition.
      systemd.services =
        let
          # Flag written only after the unmount succeeds: it is what tells
          # ExecStopPost a remount is owed, so writing it first would leave
          # it set on the busy-/shared refusal above, and ExecStopPost then
          # runs `mount` against a filesystem that was never unmounted and
          # fails the unit. A failed marker write must still abort the
          # transition (exit 1): otherwise hibernation proceeds with /shared
          # mounted again, defeating the whole guard.
          sharedUmountBeforeHibernate = pkgs.writeShellScript "shared-umount-before-hibernate" ''
            ${pkgs.util-linux}/bin/mountpoint -q /shared || exit 0
            ${pkgs.util-linux}/bin/umount /shared || exit 1
            if ${pkgs.coreutils}/bin/touch /run/shared-remount-after-sleep; then
              exit 0
            fi
            echo "songbird: failed to record the hibernate-remount marker after unmounting /shared; remounting and aborting this sleep transition" >&2
            ${pkgs.util-linux}/bin/mount /shared || echo "songbird: recovery remount of /shared failed; run 'mount /shared' by hand" >&2
            exit 1
          '';
          # Retries cover the volume not being re-enumerated yet on resume;
          # exhausting them still fails the unit, per the no-"-" note above.
          sharedRemountAfterSleep = pkgs.writeShellScript "shared-remount-after-sleep" ''
            [ -e /run/shared-remount-after-sleep ] || exit 0
            ${pkgs.coreutils}/bin/rm -f /run/shared-remount-after-sleep
            for _ in 1 2 3; do
              ${pkgs.util-linux}/bin/mount /shared && exit 0
              ${pkgs.coreutils}/bin/sleep 1
            done
            echo "songbird: failed to remount /shared after resume; run 'mount /shared' by hand" >&2
            exit 1
          '';
        in
        lib.mkMerge [
          (lib.genAttrs
            [
              "systemd-hibernate"
              "systemd-hybrid-sleep"
              "systemd-suspend-then-hibernate"
            ]
            (_: {
              serviceConfig = {
                ExecStartPre = [ sharedUmountBeforeHibernate ];
                ExecStopPost = [ sharedRemountAfterSleep ];
              };
            })
          )
          {
            # Conditional, not required: /data is nofail here, but Requires= and
            # RequiresMountsFor= (which emits its own Requires=) ignore that, so
            # an absent or unopened drive failed this unit too, and the chown then
            # landed on the bare mount point data.mount leaves behind on the root
            # filesystem rather than on the volume. The condition leaves the unit
            # inactive instead of failed, so recovering the mount by hand needs
            # `systemctl start data-ownership.service`.
            "data-ownership" = {
              description = "Ensure /data ownership matches primary user";
              wantedBy = [ "multi-user.target" ];
              after = [ "data.mount" ];
              unitConfig.ConditionPathIsMountPoint = "/data";
              serviceConfig = {
                Type = "oneshot";
                ExecStart = "${pkgs.coreutils}/bin/chown ${owner}:${ownerGroup} /data";
              };
            };
          }
        ];
    };
}

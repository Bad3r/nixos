## Appliance Image

The `image/repart.nix` module can also be used to build self-contained [software appliances](https://en.wikipedia.org/wiki/Software_appliance).

The generation based update mechanism of NixOS is not suited for appliances. Updates of appliances are usually either performed by replacing the entire image with a new one or by updating partitions via an A/B scheme. See the [Chrome OS update process](https://chromium.googlesource.com/aosp/platform/system/update_engine/+/HEAD/README.md) for an example of how to achieve this. The appliance image built in the following example does not contain a `configuration.nix` and thus you will not be able to call `nixos-rebuild` from this system. Furthermore, it uses a [Unified Kernel Image](https://uapi-group.org/specifications/specs/unified_kernel_image/).

```programlisting
let
  pkgs = import <nixpkgs> { };
  efiArch = pkgs.stdenv.hostPlatform.efiArch;
in
(pkgs.nixos [
  (
    {
      config,
      lib,
      pkgs,
      modulesPath,
      ...
    }:
    {

      imports = [ "${modulesPath}/image/repart.nix" ];

      boot.loader.grub.enable = false;

      fileSystems."/".device = "/dev/disk/by-label/nixos";

      image.repart = {
        name = "image";
        partitions = {
          "esp" = {
            contents = {
              "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI".source =
                "${pkgs.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";

              "/EFI/Linux/${config.system.boot.loader.ukiFile}".source =
                "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
            };
            repartConfig = {
              Type = "esp";
              Format = "vfat";
              SizeMinBytes = "96M";
            };
          };
          "root" = {
            storePaths = [ config.system.build.toplevel ];
            repartConfig = {
              Type = "root";
              Format = "ext4";
              Label = "nixos";
              Minimize = "guess";
            };
          };
        };
      };

    }
  )
]).image
```

# Configuration

This chapter describes how to configure various aspects of a NixOS machine through the configuration file `/etc/nixos/configuration.nix`. As described in [_Changing the Configuration_](#sec-changing-config "Changing the Configuration"), changes to this file only take effect after you run **nixos-rebuild**.

**Table of Contents**

[Configuration Syntax](#sec-configuration-syntax)

[Package Management](#sec-package-management)

[User Management](#sec-user-management)

[File Systems](#ch-file-systems)

[X Window System](#sec-x11)

[Wayland](#sec-wayland)

[GPU acceleration](#sec-gpu-accel)

[Xfce Desktop Environment](#sec-xfce)

[Networking](#sec-networking)

[Linux Kernel](#sec-kernel-config)

[Subversion](#module-services-subversion)

[GNOME Desktop](#chap-gnome)

[Pantheon Desktop](#chap-pantheon)

[External Bootloader Backends](#sec-bootloader-external)

[Clevis](#module-boot-clevis)

[Garage](#module-services-garage)

[YouTrack](#module-services-youtrack)

[Szurubooru](#module-services-szurubooru)

[Suwayomi-Server](#module-services-suwayomi-server)

[strfry](#module-services-strfry)

[Plausible](#module-services-plausible)

[Pingvin Share](#module-services-pingvin-share)

[Pi-hole Web Dashboard](#module-services-web-apps-pihole-web)

[Pict-rs](#module-services-pict-rs)

[OpenCloud](#module-services-opencloud)

[Nextcloud](#module-services-nextcloud)

[Matomo](#module-services-matomo)

[Lemmy](#module-services-lemmy)

[Keycloak](#module-services-keycloak)

[Jitsi Meet](#module-services-jitsi-meet)

[Honk](#module-services-honk)

[Hatsu](#module-services-hatsu)

[Grocy](#module-services-grocy)

[GoToSocial](#module-services-gotosocial)

[Glance](#module-services-glance)

[FileSender](#module-services-filesender)

[Discourse](#module-services-discourse)

[Davis](#module-services-davis)

[Castopod](#module-services-castopod)

[c2FmZQ](#module-services-c2fmzq)

[Akkoma](#module-services-akkoma)

[systemd-lock-handler](#module-services-systemd-lock-handler)

[kerberos_server](#module-services-kerberos-server)

[Meilisearch](#module-services-meilisearch)

[Yggdrasil](#module-services-networking-yggdrasil)

[uMurmur](#module-service-umurmur)

[Prosody](#module-services-prosody)

[Pleroma](#module-services-pleroma)

[pihole-FTL](#module-services-networking-pihole-ftl)

[Netbird server](#module-services-netbird-server)

[Netbird](#module-services-netbird)

[Mosquitto](#module-services-mosquitto)

[Jottacloud Command-line Tool](#module-services-jotta-cli)

[GNS3 Server](#module-services-gns3-server)

[Firefox Sync server](#module-services-firefox-syncserver)

[DNS-over-HTTPS Server](#module-service-doh-server)

[Dnsmasq](#module-services-networking-dnsmasq)

[🦀 crab-hole](#module-services-crab-hole)

[atalkd](#module-services-atalkd)

[Anubis](#module-services-anubis)

[Samba](#module-services-samba)

[Litestream](#module-services-litestream)

[Prometheus exporters](#module-services-prometheus-exporters)

[parsedmarc](#module-services-parsedmarc)

[OCS Inventory Agent](#module-services-ocsinventory-agent)

[Goss](#module-services-goss)

[Cert Spotter](#module-services-certspotter)

[WeeChat](#module-services-weechat)

[Taskserver](#module-services-taskserver)

[Paisa](#module-services-paisa)

[GitLab](#module-services-gitlab)

[Forgejo](#module-forgejo)

[Dump1090-fa](#module-services-dump1090-fa)

[Apache Kafka](#module-services-apache-kafka)

[Anki Sync Server](#module-services-anki-sync-server)

[Matrix](#module-services-matrix)

[Mjolnir (Matrix Moderation Tool)](#module-services-mjolnir)

[Mautrix-Whatsapp](#module-services-mautrix-whatsapp)

[Mautrix-Signal](#module-services-mautrix-signal)

[Maubot](#module-services-maubot)

[Draupnir (Matrix Moderation Bot)](#module-services-draupnir)

[Mailman](#module-services-mailman)

[Trezor](#trezor)

[Customizing display configuration](#module-hardware-display)

[Emacs](#module-services-emacs)

[Livebook](#module-services-livebook)

[Blackfire profiler](#module-services-blackfire)

[Athens](#module-athens)

[Flatpak](#module-services-flatpak)

[TigerBeetle](#module-services-tigerbeetle)

[PostgreSQL](#module-postgresql)

[FoundationDB](#module-services-foundationdb)

[BorgBackup](#module-borgbase)

[SSL/TLS Certificates with ACME](#module-security-acme)

[Oh my ZSH](#module-programs-zsh-ohmyzsh)

[Plotinus](#module-program-plotinus)

[Digital Bitbox](#module-programs-digitalbitbox)

[Input Methods](#module-services-input-methods)

[Profiles](#ch-profiles)

[Mattermost](#sec-mattermost)

[Kubernetes](#sec-kubernetes)

## Additional installation notes

### Booting from a USB flash drive

The image has to be written verbatim to the USB flash drive for it to be bootable on UEFI and BIOS systems. Here are the recommended tools to do that.

#### Creating bootable USB flash drive with a graphical tool

Etcher is a popular and user-friendly tool. It works on Linux, Windows and macOS.

Download it from [balena.io](https://www.balena.io/etcher/), start the program, select the downloaded NixOS ISO, then select the USB flash drive and flash it.

### Warning

Etcher reports errors and usage statistics by default, which can be disabled in the settings.

An alternative is [USBImager](https://bztsrc.gitlab.io/usbimager), which is very simple and does not connect to the internet. Download the version with write-only (wo) interface for your system. Start the program, select the image, select the USB flash drive and click “Write”.

#### Creating bootable USB flash drive from a Terminal on Linux

1.  Plug in the USB flash drive.

2.  Find the corresponding device with `lsblk`. You can distinguish them by their size.

3.  Make sure all partitions on the device are properly unmounted. Replace `sdX` with your device (e.g. `sdb`).

```programlisting
sudo umount /dev/sdX*
```

4.  Then use the `dd` utility to write the image to the USB flash drive.

```programlisting
sudo dd bs=4M conv=fsync oflag=direct status=progress if=<path-to-image> of=/dev/sdX
```

#### Creating bootable USB flash drive from a Terminal on macOS

1.  Plug in the USB flash drive.

2.  Find the corresponding device with `diskutil list`. You can distinguish them by their size.

3.  Make sure all partitions on the device are properly unmounted. Replace `diskX` with your device (e.g. `disk1`).

```programlisting
diskutil unmountDisk diskX
```

4.  Then use the `dd` utility to write the image to the USB flash drive.

```programlisting
sudo dd if=<path-to-image> of=/dev/rdiskX bs=4m
```

After `dd` completes, a GUI dialog “The disk you inserted was not readable by this computer” will pop up, which can be ignored.

### Note

Using the ‘raw’ `rdiskX` device instead of `diskX` with dd completes in minutes instead of hours.

5.  Eject the disk when it is finished.

```programlisting
diskutil eject /dev/diskX
```

### Booting from the “netboot” media (PXE)

Advanced users may wish to install NixOS using an existing PXE or iPXE setup.

These instructions assume that you have an existing PXE or iPXE infrastructure and want to add the NixOS installer as another option. To build the necessary files from your current version of nixpkgs, you can run:

```programlisting
nix-build -A netboot.x86_64-linux '<nixpkgs/nixos/release.nix>'
```

This will create a `result` directory containing:

- `bzImage` – the Linux kernel

- `initrd` – the initrd file

- `netboot.ipxe` – an example ipxe script demonstrating the appropriate kernel command line arguments for this image

If you’re using plain PXE, configure your boot loader to use the `bzImage` and `initrd` files and have it provide the same kernel command line arguments found in `netboot.ipxe`.

If you’re using iPXE, depending on how your HTTP/FTP/etc. server is configured you may be able to use `netboot.ipxe` unmodified, or you may need to update the paths to the files to match your server’s directory layout.

In the future we may begin making these files available as build products from hydra at which point we will update this documentation with instructions on how to obtain them either for placing on a dedicated TFTP server or to boot them directly over the internet.

### “Booting” into NixOS via kexec

In some cases, your system might already be booted into/preinstalled with another Linux distribution, and booting NixOS by attaching an installation image is quite a manual process.

This is particularly useful for (cloud) providers where you can’t boot a custom image, but get some Debian or Ubuntu installation.

In these cases, it might be easier to use `kexec` to “jump into NixOS” from the running system, which only assumes `bash` and `kexec` to be installed on the machine.

Note that kexec may not work correctly on some hardware, as devices are not fully re-initialized in the process. In practice, this however is rarely the case.

To build the necessary files from your current version of nixpkgs, you can run:

```programlisting
nix-build -A kexec.x86_64-linux '<nixpkgs/nixos/release.nix>'
```

This will create a `result` directory containing the following:

- `bzImage` (the Linux kernel)

- `initrd` (the initrd file)

- `kexec-boot` (a shellscript invoking `kexec`)

These three files are meant to be copied over to the other already running Linux Distribution.

Note its symlinks pointing elsewhere, so `cd` in, and use `scp * root@$destination` to copy it over, rather than rsync.

Once you finished copying, execute `kexec-boot` _on the destination_, and after some seconds, the machine should be booting into an (ephemeral) NixOS installation medium.

In case you want to describe your own system closure to kexec into, instead of the default installer image, you can build your own `configuration.nix`:

```programlisting
{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/netboot/netboot-minimal.nix") ];

  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = [ "my-ssh-pubkey" ];
}
```

```programlisting
nix-build '<nixpkgs/nixos>' \
  --arg configuration ./configuration.nix
  --attr config.system.build.kexecTree
```

Make sure your `configuration.nix` does still import `netboot-minimal.nix` (or `netboot-base.nix`).

### Installing in a VirtualBox guest

Installing NixOS into a VirtualBox guest is convenient for users who want to try NixOS without installing it on bare metal. If you want to set up a VirtualBox guest, follow these instructions:

1.  Add a New Machine in VirtualBox with OS Type “Linux / Other Linux”

2.  Base Memory Size: 768 MB or higher.

3.  New Hard Disk of 10 GB or higher.

4.  Mount the CD-ROM with the NixOS ISO (by clicking on CD/DVD-ROM)

5.  Click on Settings / System / Processor and enable PAE/NX

6.  Click on Settings / System / Acceleration and enable “VT-x/AMD-V” acceleration

7.  Click on Settings / Display / Screen and select VMSVGA as Graphics Controller

8.  Save the settings, start the virtual machine, and continue installation like normal

There are a few modifications you should make in configuration.nix. Enable booting:

```programlisting
{ boot.loader.grub.device = "/dev/sda"; }
```

Also remove the fsck that runs at startup. It will always fail to run, stopping your boot until you press `*`.

```programlisting
{ boot.initrd.checkJournalingFS = false; }
```

Shared folders can be given a name and a path in the host system in the VirtualBox settings (Machine / Settings / Shared Folders, then click on the “Add” icon). Add the following to the `/etc/nixos/configuration.nix` to auto-mount them. If you do not add `"nofail"`, the system will not boot properly.

```programlisting
{ config, pkgs, ... }:
{
  fileSystems."/virtualboxshare" = {
    fsType = "vboxsf";
    device = "nameofthesharedfolder";
    options = [
      "rw"
      "nofail"
    ];
  };
}
```

The folder will be available directly under the root directory.

### Installing from another Linux distribution

Because Nix (the package manager) & Nixpkgs (the Nix packages collection) can both be installed on any (most?) Linux distributions, they can be used to install NixOS in various creative ways. You can, for instance:

1.  Install NixOS on another partition, from your existing Linux distribution (without the use of a USB or optical device!)

2.  Install NixOS on the same partition (in place!), from your existing non-NixOS Linux distribution using `NIXOS_LUSTRATE`.

3.  Install NixOS on your hard drive from the Live CD of any Linux distribution.

The first steps to all these are the same:

1.  Install the Nix package manager:

    Short version:

    ```programlisting
    $ curl -L https://nixos.org/nix/install | sh
    $ . $HOME/.nix-profile/etc/profile.d/nix.sh # …or open a fresh shell

    ```

    More details in the [Nix manual](https://nixos.org/nix/manual/#chap-quick-start)

2.  Switch to the NixOS channel:

    If you’ve just installed Nix on a non-NixOS distribution, you will be on the `nixpkgs` channel by default.

    ```programlisting
    $ nix-channel --list
    nixpkgs https://nixos.org/channels/nixpkgs-unstable
    ```

    As that channel gets released without running the NixOS tests, it will be safer to use the `nixos-*` channels instead:

    ```programlisting
    $ nix-channel --add https://nixos.org/channels/nixos-<version> nixpkgs
    ```

    Where `<version>` corresponds to the latest version available on [channels.nixos.org](https://channels.nixos.org/).

    You may want to throw in a `nix-channel --update` for good measure.

3.  Install the NixOS installation tools:

    You’ll need `nixos-generate-config` and `nixos-install`, but this also makes some man pages and `nixos-enter` available, just in case you want to chroot into your NixOS partition. NixOS installs these by default, but you don’t have NixOS yet…

    ```programlisting
    $ nix-env -f '<nixpkgs>' -iA nixos-install-tools
    ```

4.  ### Note

    The following 5 steps are only for installing NixOS to another partition. For installing NixOS in place using `NIXOS_LUSTRATE`, skip ahead.

    Prepare your target partition:

    At this point it is time to prepare your target partition. Please refer to the partitioning, file-system creation, and mounting steps of [_Installing NixOS_](#sec-installation "Installing NixOS")

    If you’re about to install NixOS in place using `NIXOS_LUSTRATE` there is nothing to do for this step.

5.  Generate your NixOS configuration:

    ```programlisting
    $ sudo `which nixos-generate-config` --root /mnt
    ```

    You’ll probably want to edit the configuration files. Refer to the `nixos-generate-config` step in [_Installing NixOS_](#sec-installation "Installing NixOS") for more information.

    Consider setting up the NixOS bootloader to give you the ability to boot on your existing Linux partition. For instance, if you’re using GRUB and your existing distribution is running Ubuntu, you may want to add something like this to your `configuration.nix`:

    ```programlisting
    {
      boot.loader.grub.extraEntries = ''
        menuentry "Ubuntu" {
          search --set=ubuntu --fs-uuid 3cc3e652-0c1f-4800-8451-033754f68e6e
          configfile "($ubuntu)/boot/grub/grub.cfg"
        }
      '';
    }
    ```

    (You can find the appropriate UUID for your partition in `/dev/disk/by-uuid`)

6.  Create the `nixbld` group and user on your original distribution:

    ```programlisting
    $ sudo groupadd -g 30000 nixbld
    $ sudo useradd -u 30000 -g nixbld -G nixbld nixbld
    ```

7.  Download/build/install NixOS:

    ### Warning

    Once you complete this step, you might no longer be able to boot on existing systems without the help of a rescue USB drive or similar.

    ### Note

    On some distributions there are separate PATHS for programs intended only for root. In order for the installation to succeed, you might have to use `PATH="$PATH:/usr/sbin:/sbin"` in the following command.

    ```programlisting
    $ sudo PATH="$PATH" `which nixos-install` --root /mnt
    ```

    Again, please refer to the `nixos-install` step in [_Installing NixOS_](#sec-installation "Installing NixOS") for more information.

    That should be it for installation to another partition!

8.  Optionally, you may want to clean up your non-NixOS distribution:

    ```programlisting
    $ sudo userdel nixbld
    $ sudo groupdel nixbld
    ```

    If you do not wish to keep the Nix package manager installed either, run something like `sudo rm -rv ~/.nix-* /nix` and remove the line that the Nix installer added to your `~/.profile`.

9.  ### Note

    The following steps are only for installing NixOS in place using `NIXOS_LUSTRATE`:

    Generate your NixOS configuration:

    ```programlisting
    $ sudo `which nixos-generate-config`
    ```

    Note that this will place the generated configuration files in `/etc/nixos`. You’ll probably want to edit the configuration files. Refer to the `nixos-generate-config` step in [_Installing NixOS_](#sec-installation "Installing NixOS") for more information.

    ### Note

    On [UEFI](https://en.wikipedia.org/wiki/UEFI) systems, check that your `/etc/nixos/hardware-configuration.nix` did the right thing with the [EFI System Partition](https://en.wikipedia.org/wiki/EFI_system_partition). In NixOS, by default, both [systemd-boot](https://systemd.io/BOOT/) and [grub](https://www.gnu.org/software/grub/index.html) expect it to be mounted on `/boot`. However, the configuration generator bases its [`fileSystems`](options.html#opt-fileSystems) configuration on the current mount points at the time it is run. If the current system and NixOS’s bootloader configuration don’t agree on where the [EFI System Partition](https://en.wikipedia.org/wiki/EFI_system_partition) is to be mounted, you’ll need to manually alter the mount point in `hardware-configuration.nix` before building the system closure.

    ### Note

    The lustrate process will not work if the [`boot.initrd.systemd.enable`](options.html#opt-boot.initrd.systemd.enable) option is set to `true`. If you want to use this option, wait until after the first boot into the NixOS system to enable it and rebuild.

    You’ll likely want to set a root password for your first boot using the configuration files because you won’t have a chance to enter a password until after you reboot. You can initialize the root password to an empty one with this line: (and of course don’t forget to set one once you’ve rebooted or to lock the account with `sudo passwd -l root` if you use `sudo`)

    ```programlisting
    { users.users.root.initialHashedPassword = ""; }
    ```

10. Build the NixOS closure and install it in the `system` profile:

    ```programlisting
    $ nix-env -p /nix/var/nix/profiles/system -f '<nixpkgs/nixos>' -I nixos-config=/etc/nixos/configuration.nix -iA system
    ```

11. Change ownership of the `/nix` tree to root (since your Nix install was probably single user):

    ```programlisting
    $ sudo chown -R 0:0 /nix
    ```

12. Set up the `/etc/NIXOS` and `/etc/NIXOS_LUSTRATE` files:

    `/etc/NIXOS` officializes that this is now a NixOS partition (the bootup scripts require its presence).

    `/etc/NIXOS_LUSTRATE` tells the NixOS bootup scripts to move _everything_ that’s in the root partition to `/old-root`. This will move your existing distribution out of the way in the very early stages of the NixOS bootup. There are exceptions (we do need to keep NixOS there after all), so the NixOS lustrate process will not touch:
    - The `/nix` directory

    - The `/boot` directory

    - Any file or directory listed in `/etc/NIXOS_LUSTRATE` (one per line)

    ### Note

    The act of “lustrating” refers to the wiping of the existing distribution. Creating `/etc/NIXOS_LUSTRATE` can also be used on NixOS to remove all mutable files from your root partition (anything that’s not in `/nix` or `/boot` gets “lustrated” on the next boot.

    lustrate /ˈlʌstreɪt/ verb.

    purify by expiatory sacrifice, ceremonial washing, or some other ritual action.

    Let’s create the files:

    ```programlisting
    $ sudo touch /etc/NIXOS
    $ sudo touch /etc/NIXOS_LUSTRATE
    ```

    Let’s also make sure the NixOS configuration files are kept once we reboot on NixOS:

    ```programlisting
    $ echo etc/nixos | sudo tee -a /etc/NIXOS_LUSTRATE
    ```

13. Finally, install NixOS’s boot system, backing up the current boot system’s files in the process.

    The details of this step can vary depending on the bootloader configuration in NixOS and the bootloader in use by the current system.

    The commands below should work for:
    - [BIOS](https://en.wikipedia.org/wiki/BIOS) systems.

    - [UEFI](https://en.wikipedia.org/wiki/UEFI) systems where both the current system and NixOS mount the [EFI System Partition](https://en.wikipedia.org/wiki/EFI_system_partition) on `/boot`. Both [systemd-boot](https://systemd.io/BOOT/) and [grub](https://www.gnu.org/software/grub/index.html) expect this by default in NixOS, but other distributions vary.

    ### Warning

    Once you complete this step, your current distribution will no longer be bootable! If you didn’t get all the NixOS configuration right, especially those settings pertaining to boot loading and root partition, NixOS may not be bootable either. Have a USB rescue device ready in case this happens.

    ### Warning

    On [UEFI](https://en.wikipedia.org/wiki/UEFI) systems, anything on the [EFI System Partition](https://en.wikipedia.org/wiki/EFI_system_partition) will be removed by these commands, such as other coexisting OS’s bootloaders.

    ```programlisting
    $ sudo mkdir /boot.bak && sudo mv /boot/* /boot.bak &&
    sudo NIXOS_INSTALL_BOOTLOADER=1 /nix/var/nix/profiles/system/bin/switch-to-configuration boot
    ```

    Cross your fingers, reboot, hopefully you should get a NixOS prompt!

    In other cases, most commonly where the [EFI System Partition](https://en.wikipedia.org/wiki/EFI_system_partition) of the current system is instead mounted on `/boot/efi`, the goal is to:
    - Make sure `/boot` (and the [EFI System Partition](https://en.wikipedia.org/wiki/EFI_system_partition), if mounted elsewhere) are mounted how the NixOS configuration would mount them.

    - Clear them of files related to the current system, backing them up outside of `/boot`. NixOS will move the backups into `/old-root` along with everything else when it first boots.

    - Instruct the NixOS closure built earlier to install its bootloader with:

      ```programlisting
      sudo NIXOS_INSTALL_BOOTLOADER=1 /nix/var/nix/profiles/system/bin/switch-to-configuration boot
      ```

14. If for some reason you want to revert to the old distribution, you’ll need to boot on a USB rescue disk and do something along these lines:

    ```programlisting
    # mkdir root

    # mount /dev/sdaX root

    # mkdir root/nixos-root

    # mv -v root/* root/nixos-root/

    # mv -v root/nixos-root/old-root/* root/

    # mv -v root/boot.bak root/boot  # We had renamed this by hand earlier

    # umount root

    # reboot

    ```

    This may work as is or you might also need to reinstall the boot loader.

    And of course, if you’re happy with NixOS and no longer need the old distribution:

    ```programlisting
    sudo rm -rf /old-root
    ```

15. It’s also worth noting that this whole process can be automated. This is especially useful for Cloud VMs, where provider do not provide NixOS. For instance, [nixos-infect](https://github.com/elitak/nixos-infect) uses the lustrate process to convert Digital Ocean droplets to NixOS from other distributions automatically.

### Installing behind a proxy

To install NixOS behind a proxy, do the following before running `nixos-install`.

1.  Update proxy configuration in `/mnt/etc/nixos/configuration.nix` to keep the internet accessible after reboot.

    ```programlisting
    {
      networking.proxy.default = "http://user:password@proxy:port/";
      networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";
    }
    ```

2.  Setup the proxy environment variables in the shell where you are running `nixos-install`.

    ```programlisting
    # proxy_url="http://user:password@proxy:port/"

    # export http_proxy="$proxy_url"

    # export HTTP_PROXY="$proxy_url"

    # export https_proxy="$proxy_url"

    # export HTTPS_PROXY="$proxy_url"

    ```

### Note

If you are switching networks with different proxy configurations, use the `specialisation` option in `configuration.nix` to switch proxies at runtime. Refer to [Appendix A](options.html "Appendix A. Configuration Options") for more information.

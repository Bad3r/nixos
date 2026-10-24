{ lib, mediaDir }:
guest:
let
  windows = guest.kind == "windows";
  spice = guest.display == "spice";
  # The vdagent channel carries clipboard, file transfer, and display resizing.
  agentChannel = spice && guest.trust == "trusted";
  yesNo = value: if value then "yes" else "no";
  letter = index: builtins.substring index 1 "abcdefghijklmnopqrstuvwxyz";

  diskNames = lib.attrNames guest.disks;
  virtioDisks = lib.filter (disk: guest.disks.${disk}.bus == "virtio") diskNames;
  sataDisks = lib.filter (disk: guest.disks.${disk}.bus == "sata") diskNames;
  # Media share the SATA bus with SATA disks and boot after every disk.
  targets =
    lib.listToAttrs (lib.imap0 (index: disk: lib.nameValuePair disk "vd${letter index}") virtioDisks)
    // lib.listToAttrs (lib.imap0 (index: disk: lib.nameValuePair disk "sd${letter index}") sataDisks);
  mediaTarget = index: "sd${letter (lib.length sataDisks + index)}";

  diskXml = index: disk: ''
    <disk type="file" device="disk">
      <driver name="qemu" type="qcow2" discard="unmap"/>
      <source file="${guest.stateDir}/${disk}.qcow2"/>
      <target dev="${targets.${disk}}" bus="${guest.disks.${disk}.bus}"/>
      <boot order="${toString (index + 1)}"/>
    </disk>
  '';

  # Optional, so a pruned file never blocks a start; relabel="no" keeps
  # libvirt from chowning the shared 0644 copy.
  mediaXml = index: media: ''
    <disk type="file" device="cdrom">
      <driver name="qemu" type="raw"/>
      <source file="${mediaDir}/${media}" startupPolicy="optional">
        <seclabel model="dac" relabel="no"/>
      </source>
      <target dev="${mediaTarget index}" bus="sata"/>
      <readonly/>
      <boot order="${toString (lib.length diskNames + index + 1)}"/>
    </disk>
  '';

  interfaceXml = nic: interface: ''
    <interface type="network">
      <mac address="${guest.mac.${nic}}"/>
      <source network="${interface.network}"/>
      <model type="virtio"/>
    </interface>
  '';

  # No listen element: qemu.conf's spice_auto_unix_socket gives the console a
  # unix socket that only libvirt clients reach.
  displayXml =
    if spice then
      ''
        <graphics type="spice">
          <image compression="off"/>
          <clipboard copypaste="${yesNo guest.clipboard}"/>
          <filetransfer enable="${yesNo guest.fileTransfer}"/>
        </graphics>
        <video>
          <model type="virtio" heads="1" primary="yes"/>
        </video>
        <input type="tablet" bus="usb"/>
        <sound model="ich9">
          <audio id="1"/>
        </sound>
        <audio id="1" type="spice"/>
      ''
      + lib.optionalString agentChannel ''
        <channel type="spicevmc">
          <target type="virtio" name="com.redhat.spice.0"/>
        </channel>
      ''
      + lib.optionalString guest.usbRedirection ''
        <redirdev bus="usb" type="spicevmc"/>
        <redirdev bus="usb" type="spicevmc"/>
      ''
    else
      ''
        <video>
          <model type="none"/>
        </video>
      '';

  hyperv = lib.optionalString windows ''
    <hyperv mode="custom">
      <relaxed state="on"/>
      <vapic state="on"/>
      <spinlocks state="on" retries="8191"/>
      <vpindex state="on"/>
      <runtime state="on"/>
      <synic state="on"/>
      <stimer state="on"/>
      <frequencies state="on"/>
      <tlbflush state="on"/>
      <ipi state="on"/>
    </hyperv>
    <vmport state="off"/>
  '';

  # A guest that sleeps sits in pmsuspended instead of shutting down or saving.
  pm = ''
    <pm>
      <suspend-to-mem enabled="no"/>
      <suspend-to-disk enabled="no"/>
    </pm>
  '';

  render = revision: ''
    <domain type="kvm">
      <name>${guest.domainName}</name>
      <uuid>${guest.uuid}</uuid>
      <metadata>
        <wl:managed xmlns:wl="https://github.com/Bad3r/nixos/workloads" revision="${revision}"/>
      </metadata>
      <memory unit="MiB">${toString guest.memory}</memory>
      <currentMemory unit="MiB">${toString guest.memory}</currentMemory>
      <vcpu placement="static"${
        lib.optionalString (guest.cpuset != null) " cpuset=\"${guest.cpuset}\""
      }>${toString guest.vcpus}</vcpu>
      <os firmware="efi">
        <type arch="x86_64" machine="q35">hvm</type>
        <firmware>
          <feature enabled="${yesNo guest.firmware.enrolledKeys}" name="enrolled-keys"/>
          <feature enabled="${yesNo guest.firmware.secureBoot}" name="secure-boot"/>
        </firmware>
        <nvram>${guest.nvramPath}</nvram>
      </os>
      <features>
        <acpi/>
        <apic/>
        ${hyperv}
        ${lib.optionalString guest.firmware.secureBoot ''<smm state="on"/>''}
      </features>
      <cpu mode="host-passthrough" check="none" migratable="on">
        <topology sockets="1" dies="1" cores="${toString guest.vcpus}" threads="1"/>
      </cpu>
      <clock offset="${if windows then "localtime" else "utc"}">
        <timer name="rtc" tickpolicy="catchup"/>
        <timer name="pit" tickpolicy="delay"/>
        <timer name="hpet" present="no"/>
        ${lib.optionalString windows ''<timer name="hypervclock" present="yes"/>''}
      </clock>
      <on_poweroff>destroy</on_poweroff>
      <on_reboot>restart</on_reboot>
      <on_crash>destroy</on_crash>
      ${pm}
      <devices>
        <emulator>/run/libvirt/nix-emulators/qemu-system-x86_64</emulator>
        ${lib.concatStrings (lib.imap0 diskXml diskNames)}
        ${lib.concatStrings (lib.imap0 mediaXml guest.install.media)}
        <controller type="usb" model="qemu-xhci" ports="15"/>
        ${lib.concatStrings (lib.mapAttrsToList interfaceXml guest.interfaces)}
        <serial type="pty">
          <target port="0"/>
        </serial>
        <console type="pty">
          <target type="serial" port="0"/>
        </console>
        ${lib.optionalString guest.guestAgent ''
          <channel type="unix">
            <target type="virtio" name="org.qemu.guest_agent.0"/>
          </channel>
        ''}
        ${displayXml}
        ${lib.optionalString guest.firmware.tpm ''
          <tpm model="tpm-crb">
            <backend type="emulator" version="2.0" persistent_state="yes">
              <source type="dir" path="${guest.stateDir}/tpm"/>
            </backend>
          </tpm>
        ''}
        <memballoon model="virtio"/>
        <rng model="virtio">
          <backend model="random">/dev/urandom</backend>
        </rng>
        ${guest.extraDevicesXml}
      </devices>
    </domain>
  '';
in
# The marker records a digest of the definition, so the live XML of a running
# guest tells which definition it booted with.
render (builtins.hashString "sha256" (render ""))

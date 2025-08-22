## Activate unattended decryption of a resource at boot

In order to activate unattended decryption of a resource at boot, enable the `clevis` module:

```programlisting
{ boot.initrd.clevis.enable = true; }
```

Then, specify the device you want to decrypt using a given clevis secret. Clevis will automatically try to decrypt the device at boot and will fallback to interactive unlocking if the decryption policy is not fulfilled.

```programlisting
{ boot.initrd.clevis.devices."/dev/nvme0n1p1".secretFile = ./nvme0n1p1.jwe; }
```

Only `bcachefs`, `zfs` and `luks` encrypted devices are supported at this time.

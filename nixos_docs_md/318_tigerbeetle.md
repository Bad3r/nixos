## TigerBeetle

**Table of Contents**

[Configuring](#module-services-tigerbeetle-configuring)

[Upgrading](#module-services-tigerbeetle-upgrading)

_Source:_ `modules/services/databases/tigerbeetle.nix`

_Upstream documentation:_ [https://docs.tigerbeetle.com/](https://docs.tigerbeetle.com/)

TigerBeetle is a distributed financial accounting database designed for mission critical safety and performance.

To enable TigerBeetle, add the following to your `configuration.nix`:

```programlisting
{ services.tigerbeetle.enable = true; }
```

When first started, the TigerBeetle service will create its data file at `/var/lib/tigerbeetle` unless the file already exists, in which case it will just use the existing file. If you make changes to the configuration of TigerBeetle after its data file was already created (for example increasing the replica count), you may need to remove the existing file to avoid conflicts.

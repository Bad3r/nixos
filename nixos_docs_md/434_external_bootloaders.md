## External bootloaders

It is possible to enable your own bootloader through [`boot.loader.external.installHook`](options.html#opt-boot.loader.external.installHook) which can wrap an existing bootloader.

Currently, there is no good story to compose existing bootloaders to enrich their features, e.g. SecureBoot, etc. It will be necessary to reimplement or reuse existing parts.

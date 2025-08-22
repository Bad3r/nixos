## Migration

Many services could be migrated to the modular service system, but even when the modular service system is mature, it is not necessary to migrate all services. For instance, many system-wide services are a mandatory part of a desktop system, and it doesn’t make sense to have multiple instances of them. Moving their logic into separate Nix files may still be beneficial for the efficient evaluation of configurations that don’t use those services, but that is a rather minor benefit, unless modular services potentially become the standard way to define services.

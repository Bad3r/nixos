## Quickstart

The absolute minimal configuration for the sync server looks like this:

```programlisting
{
  services.mysql.package = pkgs.mariadb;

  services.firefox-syncserver = {
    enable = true;
    secrets = builtins.toFile "sync-secrets" ''
      SYNC_MASTER_SECRET=this-secret-is-actually-leaked-to-/nix/store
    '';
    singleNode = {
      enable = true;
      hostname = "localhost";
      url = "http://localhost:5000";
    };
  };
}
```

This will start a sync server that is only accessible locally on the following url: `http://localhost:5000/1.0/sync/1.5`. See [the dedicated section](#module-services-firefox-syncserver-clients "Configuring clients to use this server") to configure your browser to use this sync server.

### Warning

This configuration should never be used in production. It is not encrypted and stores its secrets in a world-readable location.

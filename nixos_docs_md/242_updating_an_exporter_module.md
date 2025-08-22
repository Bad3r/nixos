## Updating an exporter module

Should an exporter option change at some point, it is possible to add information about the change to the exporter definition similar to `nixpkgs/nixos/modules/rename.nix`:

```programlisting
{
  config,
  lib,
  pkgs,
  options,
}:

let
  cfg = config.services.prometheus.exporters.nginx;
in
{
  port = 9113;
  extraOpts = {
    # additional module options

    # ...

  };
  serviceOpts = {
    # service configuration

    # ...

  };
  imports = [
    # 'services.prometheus.exporters.nginx.telemetryEndpoint' -> 'services.prometheus.exporters.nginx.telemetryPath'

    (lib.mkRenamedOptionModule [ "telemetryEndpoint" ] [ "telemetryPath" ])

    # removed option 'services.prometheus.exporters.nginx.insecure'

    (lib.mkRemovedOptionModule [ "insecure" ] ''
      This option was replaced by 'prometheus.exporters.nginx.sslVerify' which defaults to true.
    '')
    ({ options.warnings = options.warnings; })
  ];
}
```

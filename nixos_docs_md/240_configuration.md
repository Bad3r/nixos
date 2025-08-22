## Configuration

One of the most common exporters is the [node exporter](https://github.com/prometheus/node_exporter), it provides hardware and OS metrics from the host it’s running on. The exporter could be configured as follows:

```programlisting
{
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    enabledCollectors = [
      "logind"
      "systemd"
    ];
    disabledCollectors = [ "textfile" ];
    openFirewall = true;
    firewallFilter = "-i br0 -p tcp -m tcp --dport 9100";
  };
}
```

It should now serve all metrics from the collectors that are explicitly enabled and the ones that are [enabled by default](https://github.com/prometheus/node_exporter#enabled-by-default), via http under `/metrics`. In this example the firewall should just allow incoming connections to the exporter’s port on the bridge interface `br0` (this would have to be configured separately of course). For more information about configuration see `man configuration.nix` or search through the [available options](https://nixos.org/nixos/options.html#prometheus.exporters).

Prometheus can now be configured to consume the metrics produced by the exporter:

```programlisting
{
  services.prometheus = {
    # ...

    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [
          {
            targets = [
              "localhost:${toString config.services.prometheus.exporters.node.port}"
            ];
          }
        ];
      }
    ];

    # ...

  };
}
```

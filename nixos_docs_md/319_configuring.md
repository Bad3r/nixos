## Configuring

By default, TigerBeetle will only listen on a local interface. To configure it to listen on a different interface (and to configure it to connect to other replicas, if you’re creating more than one), you’ll have to set the `addresses` option. Note that the TigerBeetle module won’t open any firewall ports automatically, so if you configure it to listen on an external interface, you’ll need to ensure that connections can reach it:

```programlisting
{
  services.tigerbeetle = {
    enable = true;
    addresses = [ "0.0.0.0:3001" ];
  };

  networking.firewall.allowedTCPPorts = [ 3001 ];
}
```

A complete list of options for TigerBeetle can be found [here](options.html#opt-services.tigerbeetle.enable).

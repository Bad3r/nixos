## Multiple connections setup

Using the `services.netbird.clients` option, it is possible to define more than one netbird service running at the same time.

You must at least define a `port` for the service to listen on, the rest is optional:

```programlisting
{
  services.netbird.clients.wt1.port = 51830;
  services.netbird.clients.wt2.port = 51831;
}
```

see [clients](options.html#opt-services.netbird.clients) option documentation for more details.

## Configuration

It is possible to configure default settings for all instances of Anubis, via `services.anubis.defaultOptions`.

```programlisting
{
  services.anubis.defaultOptions = {
    botPolicy = {
      dnsbl = false;
    };
    settings.DIFFICULTY = 3;
  };
}
```

Note that at the moment, a custom bot policy is not merged with the baked-in one. That means to only override a setting like `dnsbl`, copying the entire bot policy is required. Check [the upstream repository](https://github.com/TecharoHQ/anubis/blob/1509b06cb921aff842e71fbb6636646be6ed5b46/cmd/anubis/botPolicies.json) for the policy.

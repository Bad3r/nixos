## Quickstart

the minimum to start lemmy is

```programlisting
{
  services.lemmy = {
    enable = true;
    settings = {
      hostname = "lemmy.union.rocks";
      database.createLocally = true;
    };
    caddy.enable = true;
  };
}
```

this will start the backend on port 8536 and the frontend on port 1234. It will expose your instance with a caddy reverse proxy to the hostname you’ve provided. Postgres will be initialized on that same instance automatically.

## Proxy configuration

Although it is possible to expose Akkoma directly, it is common practice to operate it behind an HTTP reverse proxy such as nginx.

```programlisting
{
  services.akkoma.nginx = {
    enableACME = true;
    forceSSL = true;
  };

  services.nginx = {
    enable = true;

    clientMaxBodySize = "16m";
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;
  };
}
```

Please refer to [_SSL/TLS Certificates with ACME_](#module-security-acme "SSL/TLS Certificates with ACME") for details on how to provision an SSL/TLS certificate.

### Media proxy

Without the media proxy function, Akkoma does not store any remote media like pictures or video locally, and clients have to fetch them directly from the source server.

```programlisting
{
  # Enable nginx slice module distributed with Tengine

  services.nginx.package = pkgs.tengine;

  # Enable media proxy

  services.akkoma.config.":pleroma".":media_proxy" = {
    enabled = true;
    proxy_opts.redirect_on_failure = true;
  };

  # Adjust the persistent cache size as needed:

  #  Assuming an average object size of 128 KiB, around 1 MiB

  #  of memory is required for the key zone per GiB of cache.

  # Ensure that the cache directory exists and is writable by nginx.

  services.nginx.commonHttpConfig = ''
    proxy_cache_path /var/cache/nginx/cache/akkoma-media-cache
      levels= keys_zone=akkoma_media_cache:16m max_size=16g
      inactive=1y use_temp_path=off;
  '';

  services.akkoma.nginx = {
    locations."/proxy" = {
      proxyPass = "http://unix:/run/akkoma/socket";

      extraConfig = ''
        proxy_cache akkoma_media_cache;

        # Cache objects in slices of 1 MiB

        slice 1m;
        proxy_cache_key $host$uri$is_args$args$slice_range;
        proxy_set_header Range $slice_range;

        # Decouple proxy and upstream responses

        proxy_buffering on;
        proxy_cache_lock on;
        proxy_ignore_client_abort on;

        # Default cache times for various responses

        proxy_cache_valid 200 1y;
        proxy_cache_valid 206 301 304 1h;

        # Allow serving of stale items

        proxy_cache_use_stale error timeout invalid_header updating;
      '';
    };
  };
}
```

#### Prefetch remote media

The following example enables the `MediaProxyWarmingPolicy` MRF policy which automatically fetches all media associated with a post through the media proxy, as soon as the post is received by the instance.

```programlisting
{
  services.akkoma.config.":pleroma".":mrf".policies = map (pkgs.formats.elixirConf { }).lib.mkRaw [
    "Pleroma.Web.ActivityPub.MRF.MediaProxyWarmingPolicy"
  ];
}
```

#### Media previews

Akkoma can generate previews for media.

```programlisting
{
  services.akkoma.config.":pleroma".":media_preview_proxy" = {
    enabled = true;
    thumbnail_max_width = 1920;
    thumbnail_max_height = 1080;
  };
}
```

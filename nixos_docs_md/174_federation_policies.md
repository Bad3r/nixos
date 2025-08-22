## Federation policies

Akkoma comes with a number of modules to police federation with other ActivityPub instances. The most valuable for typical users is the [`:mrf_simple`](https://docs.akkoma.dev/stable/configuration/cheatsheet/#mrf_simple) module which allows limiting federation based on instance hostnames.

This configuration snippet provides an example on how these can be used. Choosing an adequate federation policy is not trivial and entails finding a balance between connectivity to the rest of the fediverse and providing a pleasant experience to the users of an instance.

```programlisting
{
  services.akkoma.config.":pleroma" = with (pkgs.formats.elixirConf { }).lib; {
    ":mrf".policies = map mkRaw [ "Pleroma.Web.ActivityPub.MRF.SimplePolicy" ];

    ":mrf_simple" = {
      # Tag all media as sensitive

      media_nsfw = mkMap { "nsfw.weird.kinky" = "Untagged NSFW content"; };

      # Reject all activities except deletes

      reject = mkMap {
        "kiwifarms.cc" = "Persistent harassment of users, no moderation";
      };

      # Force posts to be visible by followers only

      followers_only = mkMap {
        "beta.birdsite.live" = "Avoid polluting timelines with Twitter posts";
      };
    };
  };
}
```

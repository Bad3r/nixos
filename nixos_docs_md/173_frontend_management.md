## Frontend management

Akkoma will be deployed with the `akkoma-fe` and `admin-fe` frontends by default. These can be modified by setting [`services.akkoma.frontends`](options.html#opt-services.akkoma.frontends).

The following example overrides the primary frontend’s default configuration using a custom derivation.

```programlisting
{
  services.akkoma.frontends.primary.package =
    pkgs.runCommand "akkoma-fe"
      {
        config = builtins.toJSON {
          expertLevel = 1;
          collapseMessageWithSubject = false;
          stopGifs = false;
          replyVisibility = "following";
          webPushHideIfCW = true;
          hideScopeNotice = true;
          renderMisskeyMarkdown = false;
          hideSiteFavicon = true;
          postContentType = "text/markdown";
          showNavShortcuts = false;
        };
        nativeBuildInputs = with pkgs; [
          jq
          xorg.lndir
        ];
        passAsFile = [ "config" ];
      }
      ''
        mkdir $out
        lndir ${pkgs.akkoma-frontends.akkoma-fe} $out

        rm $out/static/config.json
        jq -s add ${pkgs.akkoma-frontends.akkoma-fe}/static/config.json ${config} \
          >$out/static/config.json
      '';
}
```

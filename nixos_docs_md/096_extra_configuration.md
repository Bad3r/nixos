## Extra configuration

Not all the configuration options are available directly in this module, but you can add the other options of suwayomi-server with:

```programlisting
{ ... }:

{
  services.suwayomi-server = {
    enable = true;

    openFirewall = true;

    settings = {
      server = {
        port = 4567;
        autoDownloadNewChapters = false;
        maxSourcesInParallel = 6;
        extensionRepos = [
          "https://raw.githubusercontent.com/MY_ACCOUNT/MY_REPO/repo/index.min.json"
        ];
      };
    };
  };
}
```

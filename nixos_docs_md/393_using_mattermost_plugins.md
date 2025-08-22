## Using Mattermost plugins

You can configure Mattermost plugins by either using prebuilt binaries or by building your own. We test building and using plugins in the NixOS test suite.

Mattermost plugins are tarballs containing a system-specific statically linked Go binary and webapp resources.

Here is an example with a prebuilt plugin tarball:

```programlisting
{
  services.mattermost = {
    plugins = with pkgs; [
      # todo

      # 0.7.1

      # https://github.com/mattermost/mattermost-plugin-todo/releases/tag/v0.7.1

      (fetchurl {
        # Note: Don't unpack the tarball; the NixOS module will repack it for you.

        url = "https://github.com/mattermost-community/mattermost-plugin-todo/releases/download/v0.7.1/com.mattermost.plugin-todo-0.7.1.tar.gz";
        hash = "sha256-P+Z66vqE7FRmc2kTZw9FyU5YdLLbVlcJf11QCbfeJ84=";
      })
    ];
  };
}
```

Once the plugin is installed and the config rebuilt, you can enable this plugin in the System Console.

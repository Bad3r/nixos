## Mattermost

**Table of Contents**

[Using the Mattermost derivation](#sec-mattermost-derivation)

[Using Mattermost plugins](#sec-mattermost-plugins)

[Building Mattermost plugins](#sec-mattermost-plugins-build)

The NixOS Mattermost module lets you build [Mattermost](https://mattermost.com) instances for collaboration over chat, optionally with custom builds of plugins specific to your instance.

To enable Mattermost using Postgres, use a config like this:

```programlisting
{
  services.mattermost = {
    enable = true;

    # You can change this if you are reverse proxying.

    host = "0.0.0.0";
    port = 8065;

    # Allow modifications to the config from Mattermost.

    mutableConfig = true;

    # Override modifications to the config with your NixOS config.

    preferNixConfig = true;

    socket = {
      # Enable control with the `mmctl` socket.

      enable = true;

      # Exporting the control socket will add `mmctl` to your PATH, and export

      # MMCTL_LOCAL_SOCKET_PATH systemwide. Otherwise, you can get the socket

      # path out of `config.mattermost.socket.path` and set it manually.

      export = true;
    };

    # For example, to disable auto-installation of prepackaged plugins.

    settings.PluginSettings.AutomaticPrepackagedPlugins = false;
  };
}
```

As of NixOS 25.05, Mattermost uses peer authentication with Postgres or MySQL by default. If you previously used password auth on localhost, this will automatically be configured if your `stateVersion` is set to at least `25.05`.

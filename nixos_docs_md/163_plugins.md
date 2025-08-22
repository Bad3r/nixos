## Plugins

You can install Discourse plugins using the [`services.discourse.plugins`](options.html#opt-services.discourse.plugins) option. Pre-packaged plugins are provided in `<your_discourse_package_here>.plugins`. If you want the full suite of plugins provided through `nixpkgs`, you can also set the [`services.discourse.package`](options.html#opt-services.discourse.package) option to `pkgs.discourseAllPlugins`.

Plugins can be built with the `<your_discourse_package_here>.mkDiscoursePlugin` function. Normally, it should suffice to provide a `name` and `src` attribute. If the plugin has Ruby dependencies, however, they need to be packaged in accordance with the [Developing with Ruby](https://nixos.org/manual/nixpkgs/stable/#developing-with-ruby) section of the Nixpkgs manual and the appropriate gem options set in `bundlerEnvArgs` (normally `gemdir` is sufficient). A plugin’s Ruby dependencies are listed in its `plugin.rb` file as function calls to `gem`. To construct the corresponding `Gemfile` manually, run **bundle init**, then add the `gem` lines to it verbatim.

Much of the packaging can be done automatically by the `nixpkgs/pkgs/servers/web-apps/discourse/update.py` script - just add the plugin to the `plugins` list in the `update_plugins` function and run the script:

```programlisting
./update.py update-plugins
```

Some plugins provide [site settings](#module-services-discourse-site-settings "Site settings"). Their defaults can be configured using [`services.discourse.siteSettings`](options.html#opt-services.discourse.siteSettings), just like regular site settings. To find the names of these settings, look in the `config/settings.yml` file of the plugin repo.

For example, to add the [discourse-spoiler-alert](https://github.com/discourse/discourse-spoiler-alert) and [discourse-solved](https://github.com/discourse/discourse-solved) plugins, and disable `discourse-spoiler-alert` by default:

```programlisting
{
  services.discourse = {
    enable = true;
    hostname = "discourse.example.com";
    sslCertificate = "/path/to/ssl_certificate";
    sslCertificateKey = "/path/to/ssl_certificate_key";
    admin = {
      email = "admin@example.com";
      username = "admin";
      fullName = "Administrator";
      passwordFile = "/path/to/password_file";
    };
    mail.outgoing = {
      serverAddress = "smtp.emailprovider.com";
      port = 587;
      username = "user@emailprovider.com";
      passwordFile = "/path/to/smtp_password_file";
    };
    mail.incoming.enable = true;
    plugins = with config.services.discourse.package.plugins; [
      discourse-spoiler-alert
      discourse-solved
    ];
    siteSettings = {
      plugins = {
        spoiler_enabled = false;
      };
    };
    secretKeyBaseFile = "/path/to/secret_key_base_file";
  };
}
```

## Additional settings

Additional site settings and backend settings, for which no explicit NixOS options are provided, can be set in [`services.discourse.siteSettings`](options.html#opt-services.discourse.siteSettings) and [`services.discourse.backendSettings`](options.html#opt-services.discourse.backendSettings) respectively.

### Site settings

“Site settings” are the settings that can be changed through the Discourse UI. Their _default_ values can be set using [`services.discourse.siteSettings`](options.html#opt-services.discourse.siteSettings).

Settings are expressed as a Nix attribute set which matches the structure of the configuration in [config/site_settings.yml](https://github.com/discourse/discourse/blob/master/config/site_settings.yml). To find a setting’s path, you only need to care about the first two levels; i.e. its category (e.g. `login`) and name (e.g. `invite_only`).

Settings containing secret data should be set to an attribute set containing the attribute `_secret` - a string pointing to a file containing the value the option should be set to. See the example.

### Backend settings

Settings are expressed as a Nix attribute set which matches the structure of the configuration in [config/discourse.conf](https://github.com/discourse/discourse/blob/stable/config/discourse_defaults.conf). Empty parameters can be defined by setting them to `null`.

### Example

The following example sets the title and description of the Discourse instance and enables GitHub login in the site settings, and changes a few request limits in the backend settings:

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
    siteSettings = {
      required = {
        title = "My Cats";
        site_description = "Discuss My Cats (and be nice plz)";
      };
      login = {
        enable_github_logins = true;
        github_client_id = "a2f6dfe838cb3206ce20";
        github_client_secret._secret = /run/keys/discourse_github_client_secret;
      };
    };
    backendSettings = {
      max_reqs_per_ip_per_minute = 300;
      max_reqs_per_ip_per_10_seconds = 60;
      max_asset_reqs_per_ip_per_10_seconds = 250;
      max_reqs_per_ip_mode = "warn+block";
    };
    secretKeyBaseFile = "/path/to/secret_key_base_file";
  };
}
```

In the resulting site settings file, the `login.github_client_secret` key will be set to the contents of the `/run/keys/discourse_github_client_secret` file.

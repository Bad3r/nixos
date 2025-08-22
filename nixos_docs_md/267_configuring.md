## Configuring

GitLab depends on both PostgreSQL and Redis and will automatically enable both services. In the case of PostgreSQL, a database and a role will be created.

The default state dir is `/var/gitlab/state`. This is where all data like the repositories and uploads will be stored.

A basic configuration with some custom settings could look like this:

```programlisting
{
  services.gitlab = {
    enable = true;
    databasePasswordFile = "/var/keys/gitlab/db_password";
    initialRootPasswordFile = "/var/keys/gitlab/root_password";
    https = true;
    host = "git.example.com";
    port = 443;
    user = "git";
    group = "git";
    smtp = {
      enable = true;
      address = "localhost";
      port = 25;
    };
    secrets = {
      dbFile = "/var/keys/gitlab/db";
      secretFile = "/var/keys/gitlab/secret";
      otpFile = "/var/keys/gitlab/otp";
      jwsFile = "/var/keys/gitlab/jws";
    };
    extraConfig = {
      gitlab = {
        email_from = "gitlab-no-reply@example.com";
        email_display_name = "Example GitLab";
        email_reply_to = "gitlab-no-reply@example.com";
        default_projects_features = {
          builds = false;
        };
      };
    };
  };
}
```

If you’re setting up a new GitLab instance, generate new secrets. You for instance use `tr -dc A-Za-z0-9 < /dev/urandom | head -c 128 > /var/keys/gitlab/db` to generate a new db secret. Make sure the files can be read by, and only by, the user specified by [services.gitlab.user](options.html#opt-services.gitlab.user). GitLab encrypts sensitive data stored in the database. If you’re restoring an existing GitLab instance, you must specify the secrets secret from `config/secrets.yml` located in your GitLab state folder.

When `incoming_mail.enabled` is set to `true` in [extraConfig](options.html#opt-services.gitlab.extraConfig) an additional service called `gitlab-mailroom` is enabled for fetching incoming mail.

Refer to [Appendix A](options.html "Appendix A. Configuration Options") for all available configuration options for the [services.gitlab](options.html#opt-services.gitlab.enable) module.

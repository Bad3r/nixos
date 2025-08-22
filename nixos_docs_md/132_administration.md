## Administration

An administrative user with the username `admin` is automatically created in the `master` realm. Its initial password can be configured by setting [`services.keycloak.initialAdminPassword`](options.html#opt-services.keycloak.initialAdminPassword) and defaults to `changeme`. The password is not stored safely and should be changed immediately in the admin panel.

Refer to the [Keycloak Server Administration Guide](https://www.keycloak.org/docs/latest/server_admin/index.html) for information on how to administer your Keycloak instance.

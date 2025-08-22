## Registering Matrix users

If you want to run a server with public registration by anybody, you can then enable `services.matrix-synapse.settings.enable_registration = true;`. Otherwise, or you can generate a registration secret with **pwgen -s 64 1** and set it with [`services.matrix-synapse.settings.registration_shared_secret`](options.html#opt-services.matrix-synapse.settings.registration_shared_secret). To create a new user or admin from the terminal your client listener must be configured to use TCP sockets. Then you can run the following after you have set the secret and have rebuilt NixOS:

```programlisting
$ nix-shell -p matrix-synapse
$ register_new_matrix_user -k your-registration-shared-secret http://localhost:8008
New user localpart: your-username
Password:
Confirm password:
Make admin [no]:
Success!
```

In the example, this would create a user with the Matrix Identifier `@your-username:example.org`.

### Warning

When using [`services.matrix-synapse.settings.registration_shared_secret`](options.html#opt-services.matrix-synapse.settings.registration_shared_secret), the secret will end up in the world-readable store. Instead it’s recommended to deploy the secret in an additional file like this:

- Create a file with the following contents:

  ```programlisting
  registration_shared_secret: your-very-secret-secret
  ```

- Deploy the file with a secret-manager such as [`deployment.keys`](https://nixops.readthedocs.io/en/latest/overview.html#managing-keys) from nixops(1) or [sops-nix](https://github.com/Mic92/sops-nix/) to e.g. `/run/secrets/matrix-shared-secret` and ensure that it’s readable by `matrix-synapse`.

- Include the file like this in your configuration:

  ```programlisting
  {
    services.matrix-synapse.extraConfigFiles = [ "/run/secrets/matrix-shared-secret" ];
  }
  ```

### Note

It’s also possible to user alternative authentication mechanism such as [LDAP (via `matrix-synapse-ldap3`)](https://github.com/matrix-org/matrix-synapse-ldap3) or [OpenID](https://element-hq.github.io/synapse/latest/openid.html).

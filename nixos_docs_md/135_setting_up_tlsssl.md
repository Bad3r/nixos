## Setting up TLS/SSL

By default, Keycloak won’t accept unsecured HTTP connections originating from outside its local network.

HTTPS support requires a TLS/SSL certificate and a private key, both [PEM formatted](https://en.wikipedia.org/wiki/Privacy-Enhanced_Mail). Their paths should be set through [`services.keycloak.sslCertificate`](options.html#opt-services.keycloak.sslCertificate) and [`services.keycloak.sslCertificateKey`](options.html#opt-services.keycloak.sslCertificateKey).

### Warning

The paths should be provided as a strings, not a Nix paths, since Nix paths are copied into the world readable Nix store.

## Ensuring dependencies for services that need to be reloaded when a certificate challenges

Services that depend on ACME certificates and need to be reloaded can use one of two approaches to reload upon successful certificate acquisition or renewal:

1.  **Using the `security.acme.certs.<name>.reloadServices` option**: This will cause `systemctl try-reload-or-restart` to be run for the listed services.

2.  **Using a separate reload unit**: if you need perform more complex actions you can implement a separate reload unit but need to ensure that it lists the `acme-renew-<name>.service` unit both as `wantedBy` AND `after`. See the nginx module implementation with its `nginx-config-reload` service.

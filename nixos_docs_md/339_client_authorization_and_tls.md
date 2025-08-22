## Client authorization and TLS

By default, any user who can connect to a FoundationDB process with the correct cluster configuration can access anything. FoundationDB uses a pluggable design to transport security, and out of the box it supports a LibreSSL-based plugin for TLS support. This plugin not only does in-flight encryption, but also performs client authorization based on the given endpoint’s certificate chain. For example, a FoundationDB server may be configured to only accept client connections over TLS, where the client TLS certificate is from organization _Acme Co_ in the _Research and Development_ unit.

Configuring TLS with FoundationDB is done using the `services.foundationdb.tls` options in order to control the peer verification string, as well as the certificate and its private key.

Note that the certificate and its private key must be accessible to the FoundationDB user account that the server runs under. These files are also NOT managed by NixOS, as putting them into the store may reveal private information.

After you have a key and certificate file in place, it is not enough to simply set the NixOS module options – you must also configure the **fdb.cluster** file to specify that a given set of coordinators use TLS. This is as simple as adding the suffix **:tls** to your cluster coordinator configuration, after the port number. For example, assuming you have a coordinator on localhost with the default configuration, simply specifying:

```programlisting
XXXXXX:XXXXXX@127.0.0.1:4500:tls
```

will configure all clients and server processes to use TLS from now on.

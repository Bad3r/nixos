## SSL/TLS Certificates with ACME

**Table of Contents**

[Prerequisites](#module-security-acme-prerequisites)

[Using ACME certificates in Nginx](#module-security-acme-nginx)

[Using ACME certificates in Apache/httpd](#module-security-acme-httpd)

[Manual configuration of HTTP-01 validation](#module-security-acme-configuring)

[Configuring ACME for DNS validation](#module-security-acme-config-dns)

[Using DNS validation with web server virtual hosts](#module-security-acme-config-dns-with-vhosts)

[Using ACME with services demanding root owned certificates](#module-security-acme-root-owned)

[Regenerating certificates](#module-security-acme-regenerate)

[Fixing JWS Verification error](#module-security-acme-fix-jws)

[Ensuring dependencies for services that need to be reloaded when a certificate challenges](#module-security-acme-reload-dependencies)

NixOS supports automatic domain validation & certificate retrieval and renewal using the ACME protocol. Any provider can be used, but by default NixOS uses Let’s Encrypt. The alternative ACME client [lego](https://go-acme.github.io/lego/) is used under the hood.

Automatic cert validation and configuration for Apache and Nginx virtual hosts is included in NixOS, however if you would like to generate a wildcard cert or you are not using a web server you will have to configure DNS based validation.

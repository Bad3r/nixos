## Prerequisites

To use the ACME module, you must accept the provider’s terms of service by setting [`security.acme.acceptTerms`](options.html#opt-security.acme.acceptTerms) to `true`. The Let’s Encrypt ToS can be found [here](https://letsencrypt.org/repository/).

You must also set an email address to be used when creating accounts with Let’s Encrypt. You can set this for all certs with [`security.acme.defaults.email`](options.html#opt-security.acme.defaults.email) and/or on a per-cert basis with [`security.acme.certs.<name>.email`](options.html#opt-security.acme.certs._name_.email). This address is only used for registration and renewal reminders, and cannot be used to administer the certificates in any way.

Alternatively, you can use a different ACME server by changing the [`security.acme.defaults.server`](options.html#opt-security.acme.defaults.server) option to a provider of your choosing, or just change the server for one cert with [`security.acme.certs.<name>.server`](options.html#opt-security.acme.certs._name_.server).

You will need an HTTP server or DNS server for verification. For HTTP, the server must have a webroot defined that can serve `.well-known/acme-challenge`. This directory must be writeable by the user that will run the ACME client. For DNS, you must set up credentials with your provider/server for use with lego.

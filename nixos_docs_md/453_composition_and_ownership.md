## Composition and Ownership

Compared to traditional services, modular services are inherently more composable, by virtue of being modules and receiving a user-provided name when imported. However, composition can not end there, because services need to be able to interact with each other. This can be achieved in two ways:

1.  Users can link services together by providing the necessary NixOS configuration.

2.  Services can be compositions of other services.

These aren’t mutually exclusive. In fact, it is a good practice when developing services to first write them as individual services, and then compose them into a higher-level composition. Each of these services is a valid modular service, including their composition.

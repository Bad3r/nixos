## Notes

- The Heimdal documentation will sometimes assume that state is stored in `/var/heimdal`, but this module uses `/var/lib/heimdal` instead.

- Due to the heimdal implementation being chosen through `security.krb5.package`, it is not possible to have a system with one implementation of the client and another of the server.

- While `services.kerberos_server.settings` has a common freeform type between the two implementations, the actual settings that can be set can vary between the two implementations. To figure out what settings are available, you should consult the upstream documentation for the implementation you are using.

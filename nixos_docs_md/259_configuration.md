## Configuration

Taskserver does all of its authentication via TLS using client certificates, so you either need to roll your own CA or purchase a certificate from a known CA, which allows creation of client certificates. These certificates are usually advertised as “server certificates”.

So in order to make it easier to handle your own CA, there is a helper tool called **nixos-taskserver** which manages the custom CA along with Taskserver organisations, users and groups.

While the client certificates in Taskserver only authenticate whether a user is allowed to connect, every user has its own UUID which identifies it as an entity.

With **nixos-taskserver** the client certificate is created along with the UUID of the user, so it handles all of the credentials needed in order to setup the Taskwarrior 2 client to work with a Taskserver.

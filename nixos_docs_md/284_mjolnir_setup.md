## Mjolnir Setup

First create a new Room which will be used as a management room for Mjolnir. In this room, Mjolnir will log possible errors and debugging information. You’ll need to set this Room-ID in [services.mjolnir.managementRoom](options.html#opt-services.mjolnir.managementRoom).

Next, create a new user for Mjolnir on your homeserver, if not present already.

The Mjolnir Matrix user expects to be free of any rate limiting. See [Synapse \#6286](https://github.com/matrix-org/synapse/issues/6286) for an example on how to achieve this.

If you want Mjolnir to be able to deactivate users, move room aliases, shutdown rooms, etc. you’ll need to make the Mjolnir user a Matrix server admin.

Now invite the Mjolnir user to the management room.

It is recommended to use [Pantalaimon](https://github.com/matrix-org/pantalaimon), so your management room can be encrypted. This also applies if you are looking to moderate an encrypted room.

To enable the Pantalaimon E2E Proxy for mjolnir, enable [services.mjolnir.pantalaimon](options.html#opt-services.mjolnir.pantalaimon.enable). This will autoconfigure a new Pantalaimon instance, which will connect to the homeserver set in [services.mjolnir.homeserverUrl](options.html#opt-services.mjolnir.homeserverUrl) and Mjolnir itself will be configured to connect to the new Pantalaimon instance.

```programlisting
{
  services.mjolnir = {
    enable = true;
    homeserverUrl = "https://matrix.domain.tld";
    pantalaimon = {
      enable = true;
      username = "mjolnir";
      passwordFile = "/run/secrets/mjolnir-password";
    };
    protectedRooms = [ "https://matrix.to/#/!xxx:domain.tld" ];
    managementRoom = "!yyy:domain.tld";
  };
}
```

### Element Matrix Services (EMS)

If you are using a managed [“Element Matrix Services (EMS)”](https://ems.element.io/) server, you will need to consent to the terms and conditions. Upon startup, an error log entry with a URL to the consent page will be generated.

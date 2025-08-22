## Draupnir Setup

First create a new unencrypted, private room which will be used as the management room for Draupnir. This is the room in which moderators will interact with Draupnir and where it will log possible errors and debugging information. You’ll need to set this room ID or alias in [services.draupnir.settings.managementRoom](options.html#opt-services.draupnir.settings.managementRoom).

Next, create a new user for Draupnir on your homeserver, if one does not already exist.

The Draupnir Matrix user expects to be free of any rate limiting. See [Synapse \#6286](https://github.com/matrix-org/synapse/issues/6286) for an example on how to achieve this.

If you want Draupnir to be able to deactivate users, move room aliases, shut down rooms, etc. you’ll need to make the Draupnir user a Matrix server admin.

Now invite the Draupnir user to the management room. Draupnir will automatically try to join this room on startup.

```programlisting
{
  services.draupnir = {
    enable = true;

    settings = {
      homeserverUrl = "https://matrix.org";
      managementRoom = "!yyy:example.org";
    };

    secrets = {
      accessToken = "/path/to/secret/containing/access-token";
    };
  };
}
```

### Element Matrix Services (EMS)

If you are using a managed [“Element Matrix Services (EMS)”](https://ems.element.io/) server, you will need to consent to the terms and conditions. Upon startup, an error log entry with a URL to the consent page will be generated.

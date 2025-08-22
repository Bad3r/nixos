## Synapse Antispam Module

A Synapse module is also available to apply the same rulesets the bot uses across an entire homeserver.

To use the Antispam Module, add `matrix-synapse-plugins.matrix-synapse-mjolnir-antispam` to the Synapse plugin list and enable the `mjolnir.Module` module.

```programlisting
{
  services.matrix-synapse = {
    plugins = with pkgs; [ matrix-synapse-plugins.matrix-synapse-mjolnir-antispam ];
    extraConfig = ''
      modules:
        - module: mjolnir.Module
          config:
            # Prevent servers/users in the ban lists from inviting users on this

            # server to rooms. Default true.

            block_invites: true
            # Flag messages sent by servers/users in the ban lists as spam. Currently

            # this means that spammy messages will appear as empty to users. Default

            # false.

            block_messages: false
            # Remove users from the user directory search by filtering matrix IDs and

            # display names by the entries in the user ban list. Default false.

            block_usernames: false
            # The room IDs of the ban lists to honour. Unlike other parts of Mjolnir,

            # this list cannot be room aliases or permalinks. This server is expected

            # to already be joined to the room - Mjolnir will not automatically join

            # these rooms.

            ban_lists:
              - "!roomid:example.org"
    '';
  };
}
```

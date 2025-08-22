## Known warnings

### Logreader application only supports “file” log_type

This is because

- our module writes logs into the journal (`journalctl -t Nextcloud`)

- the Logreader application that allows reading logs in the admin panel is enabled by default and requires logs written to a file.

If you want to view logs in the admin panel, set [`services.nextcloud.settings.log_type`](options.html#opt-services.nextcloud.settings.log_type) to “file”.

If you prefer logs in the journal, disable the logreader application to shut up the “info”. We can’t really do that by default since whether apps are enabled/disabled is part of the application’s state and tracked inside the database.

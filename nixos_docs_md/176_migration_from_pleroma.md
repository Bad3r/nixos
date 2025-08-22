## Migration from Pleroma

Pleroma instances can be migrated to Akkoma either by copying the database and upload data or by pointing Akkoma to the existing data. The necessary database migrations are run automatically during startup of the service.

The configuration has to be copy‐edited manually.

Depending on the size of the database, the initial migration may take a long time and exceed the startup timeout of the system manager. To work around this issue one may adjust the startup timeout `systemd.services.akkoma.serviceConfig.TimeoutStartSec` or simply run the migrations manually:

```programlisting
pleroma_ctl migrate
```

### Copying data

Copying the Pleroma data instead of re‐using it in place may permit easier reversion to Pleroma, but allows the two data sets to diverge.

First disable Pleroma and then copy its database and upload data:

```programlisting

# Create a copy of the database

nix-shell -p postgresql --run 'createdb -T pleroma akkoma'

# Copy upload data

mkdir /var/lib/akkoma
cp -R --reflink=auto /var/lib/pleroma/uploads /var/lib/akkoma/
```

After the data has been copied, enable the Akkoma service and verify that the migration has been successful. If no longer required, the original data may then be deleted:

```programlisting

# Delete original database

nix-shell -p postgresql --run 'dropdb pleroma'

# Delete original Pleroma state

rm -r /var/lib/pleroma
```

### Re‐using data

To re‐use the Pleroma data in place, disable Pleroma and enable Akkoma, pointing it to the Pleroma database and upload directory.

```programlisting
{
  # Adjust these settings according to the database name and upload directory path used by Pleroma

  services.akkoma.config.":pleroma"."Pleroma.Repo".database = "pleroma";
  services.akkoma.config.":pleroma".":instance".upload_dir = "/var/lib/pleroma/uploads";
}
```

Please keep in mind that after the Akkoma service has been started, any migrations applied by Akkoma have to be rolled back before the database can be used again with Pleroma. This can be achieved through `pleroma_ctl ecto.rollback`. Refer to the [Ecto SQL documentation](https://hexdocs.pm/ecto_sql/Mix.Tasks.Ecto.Rollback.html) for details.

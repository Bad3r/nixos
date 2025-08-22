## Archive Processing

This module comes with the systemd service `matomo-archive-processing.service` and a timer that automatically triggers archive processing every hour. This means that you can safely [disable browser triggers for Matomo archiving](https://matomo.org/docs/setup-auto-archiving/#disable-browser-triggers-for-matomo-archiving-and-limit-matomo-reports-to-updating-every-hour) at `Administration > System > General Settings`.

With automatic archive processing, you can now also enable to [delete old visitor logs](https://matomo.org/docs/privacy/#step-2-delete-old-visitors-logs) at `Administration > System > Privacy`, but make sure that you run `systemctl start matomo-archive-processing.service` at least once without errors if you have already collected data before, so that the reports get archived before the source data gets deleted.

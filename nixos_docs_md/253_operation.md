## Operation

**By default, NixOS configures Cert Spotter to skip all certificates issued before its first launch**, because checking the entire Certificate Transparency logs requires downloading tens of terabytes of data. If you want to check the _entire_ logs for previously issued certificates, you have to set `services.certspotter.startAtEnd` to `false` and remove all previously saved log state in `/var/lib/certspotter/logs`. The downloaded logs aren’t saved, so if you add a new domain to the watchlist and want Cert Spotter to go through the logs again, you will have to remove `/var/lib/certspotter/logs` again.

After catching up with the logs, Cert Spotter will start monitoring live logs. As of October 2023, it uses around **20 Mbps** of traffic on average.

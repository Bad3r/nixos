## Known limitations

The FoundationDB setup for NixOS should currently be considered beta. FoundationDB is not new software, but the NixOS compilation and integration has only undergone fairly basic testing of all the available functionality.

- There is no way to specify individual parameters for individual **fdbserver** processes. Currently, all server processes inherit all the global **fdbmonitor** settings.

- Ruby bindings are not currently installed.

- Go bindings are not currently installed.

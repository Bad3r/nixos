## Usage

Paisa needs to have one of the following cli tools availabe in the PATH at runtime:

- ledger

- hledger

- beancount

All of these are available from nixpkgs. Currently, it is not possible to configure this in the module, but you can e.g. use systemd to give the unit access to the command at runtime.

```programlisting
{ systemd.services.paisa.path = [ pkgs.hledger ]; }
```

### Note

Paisa needs to be configured to use the correct cli tool. This is possible in the web interface (make sure to enable [`services.paisa.mutableSettings`](options.html#opt-services.paisa.mutableSettings) if you want to persist these settings between service restarts), or in [`services.paisa.settings`](options.html#opt-services.paisa.settings).

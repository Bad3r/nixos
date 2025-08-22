## Running Emacs as a Service

NixOS provides an optional **systemd** service which launches [Emacs daemon](https://www.gnu.org/software/emacs/manual/html_node/emacs/Emacs-Server.html) with the user’s login session.

_Source:_ `modules/services/editors/emacs.nix`

### Enabling the Service

To install and enable the **systemd** user service for Emacs daemon, add the following to your `configuration.nix`:

```programlisting
{ services.emacs.enable = true; }
```

The `services.emacs.package` option allows a custom derivation to be used, for example, one created by `emacsWithPackages`.

Ensure that the Emacs server is enabled for your user’s Emacs configuration, either by customizing the `server-mode` variable, or by adding `(server-start)` to `~/.emacs.d/init.el`.

To start the daemon, execute the following:

```programlisting
$ nixos-rebuild switch  # to activate the new configuration.nix

$ systemctl --user daemon-reload        # to force systemd reload

$ systemctl --user start emacs.service  # to start the Emacs daemon

```

The server should now be ready to serve Emacs clients.

### Starting the client

Ensure that the Emacs server is enabled, either by customizing the `server-mode` variable, or by adding `(server-start)` to `~/.emacs`.

To connect to the Emacs daemon, run one of the following:

```programlisting
emacsclient FILENAME
emacsclient --create-frame  # opens a new frame (window)

emacsclient --create-frame --tty  # opens a new frame on the current terminal

```

### Configuring the `EDITOR` variable

If [`services.emacs.defaultEditor`](options.html#opt-services.emacs.defaultEditor) is `true`, the `EDITOR` variable will be set to a wrapper script which launches **emacsclient**.

Any setting of `EDITOR` in the shell config files will override `services.emacs.defaultEditor`. To make sure `EDITOR` refers to the Emacs wrapper script, remove any existing `EDITOR` assignment from `.profile`, `.bashrc`, `.zshenv` or any other shell config file.

If you have formed certain bad habits when editing files, these can be corrected with a shell alias to the wrapper script:

```programlisting
alias vi=$EDITOR
```

### Per-User Enabling of the Service

In general, **systemd** user services are globally enabled by symlinks in `/etc/systemd/user`. In the case where Emacs daemon is not wanted for all users, it is possible to install the service but not globally enable it:

```programlisting
{
  services.emacs.enable = false;
  services.emacs.install = true;
}
```

To enable the **systemd** user service for just the currently logged in user, run:

```programlisting
systemctl --user enable emacs
```

This will add the symlink `~/.config/systemd/user/emacs.service`.

## Running X without a display manager

It is possible to avoid a display manager entirely and starting the X server manually from a virtual terminal. Add to your configuration:

```programlisting
{
  services.xserver.displayManager.startx = {
    enable = true;
    generateScript = true;
  };
}
```

then you can start the X server with the `startx` command.

The second option will generate a base `xinitrc` script that will run your window manager and set up the systemd user session. You can extend the script using the [extraCommands](options.html#opt-services.xserver.displayManager.startx.extraCommands) option, for example:

```programlisting
{
  services.xserver.displayManager.startx = {
    generateScript = true;
    extraCommands = ''
      xrdb -load .Xresources
      xsetroot -solid '#666661'
      xsetroot -cursor_name left_ptr
    '';
  };
}
```

or, alternatively, you can write your own from scratch in `~/.xinitrc`.

In this case, remember you’re responsible for starting the window manager, for example:

```programlisting
sxhkd &
bspwm &
```

and if you have enabled some systemd user service, you will probably want to also add these lines too:

```programlisting

# import required env variables from the current shell

systemctl --user import-environment DISPLAY XDG_SESSION_ID

# start all graphical user services

systemctl --user start nixos-fake-graphical-session.target

# start the user dbus daemon

dbus-daemon --session --address="unix:path=/run/user/$(id -u)/bus" &
```

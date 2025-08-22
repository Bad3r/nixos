## Enabling Pantheon

All of Pantheon is working in NixOS and the applications should be available, aside from a few [exceptions](https://github.com/NixOS/nixpkgs/issues/58161). To enable Pantheon, set

```programlisting
{ services.xserver.desktopManager.pantheon.enable = true; }
```

This automatically enables LightDM and Pantheon’s LightDM greeter. If you’d like to disable this, set

```programlisting
{
  services.xserver.displayManager.lightdm.greeters.pantheon.enable = false;
  services.xserver.displayManager.lightdm.enable = false;
}
```

but please be aware using Pantheon without LightDM as a display manager will break screenlocking from the UI. The NixOS module for Pantheon installs all of Pantheon’s default applications. If you’d like to not install Pantheon’s apps, set

```programlisting
{ services.pantheon.apps.enable = false; }
```

You can also use [`environment.pantheon.excludePackages`](options.html#opt-environment.pantheon.excludePackages) to remove any other app (like `elementary-mail`).

## Auto-login

The x11 login screen can be skipped entirely, automatically logging you into your window manager and desktop environment when you boot your computer.

This is especially helpful if you have disk encryption enabled. Since you already have to provide a password to decrypt your disk, entering a second password to login can be redundant.

To enable auto-login, you need to define your default window manager and desktop environment. If you wanted no desktop environment and i3 as your your window manager, you’d define:

```programlisting
{ services.displayManager.defaultSession = "none+i3"; }
```

Every display manager in NixOS supports auto-login, here is an example using lightdm for a user `alice`:

```programlisting
{
  services.xserver.displayManager.lightdm.enable = true;
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "alice";
}
```

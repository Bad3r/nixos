## Basic Usage

By default, the module creates a [`systemd`](https://www.freedesktop.org/wiki/Software/systemd/) unit which runs the chat client in a detached [`screen`](https://www.gnu.org/software/screen/) session.

This can be done by enabling the `weechat` service:

```programlisting
{ ... }:

{
  services.weechat.enable = true;
}
```

The service is managed by a dedicated user named `weechat` in the state directory `/var/lib/weechat`.

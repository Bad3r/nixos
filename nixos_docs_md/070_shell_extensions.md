## Shell Extensions

Most Shell extensions are packaged under the `gnomeExtensions` attribute. Some packages that include Shell extensions, like `gpaste`, don’t have their extension decoupled under this attribute.

You can install them like any other package:

```programlisting
{
  environment.systemPackages = [
    gnomeExtensions.dash-to-dock
    gnomeExtensions.gsconnect
    gnomeExtensions.mpris-indicator-button
  ];
}
```

Unfortunately, we lack a way for these to be managed in a completely declarative way. So you have to enable them manually with an Extensions application. It is possible to use a [GSettings override](#sec-gnome-gsettings-overrides "GSettings Overrides") for this on `org.gnome.shell.enabled-extensions`, but that will only influence the default value.

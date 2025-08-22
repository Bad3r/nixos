## GTK/Qt themes

GTK themes can be installed either to user profile or system-wide (via `environment.systemPackages`). To make Qt 5 applications look similar to GTK ones, you can use the following configuration:

```programlisting
{
  qt.enable = true;
  qt.platformTheme = "gtk2";
  qt.style = "gtk2";
}
```

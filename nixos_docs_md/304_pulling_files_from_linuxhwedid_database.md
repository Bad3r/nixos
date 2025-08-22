## Pulling files from linuxhw/EDID database

`hardware.display.edid.linuxhw` utilizes `pkgs.linuxhw-edid-fetcher` to extract EDID files from https://github.com/linuxhw/EDID based on simple string/regexp search identifying exact entries:

```programlisting
{
  hardware.display.edid.linuxhw."PG278Q_2014" = [
    "PG278Q"
    "2014"
  ];

  /*
    equals:
    hardware.display.edid.packages = [
      (pkgs.linuxhw-edid-fetcher.override {
        displays = {
          "PG278Q_2014" = [ "PG278Q" "2014" ];
        };
      })
    ];
  */
}
```

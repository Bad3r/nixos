## Upload filters

This example strips GPS and location metadata from uploads, deduplicates them and anonymises the the file name.

```programlisting
{
  services.akkoma.config.":pleroma"."Pleroma.Upload".filters =
    map (pkgs.formats.elixirConf { }).lib.mkRaw
      [
        "Pleroma.Upload.Filter.Exiftool"
        "Pleroma.Upload.Filter.Dedupe"
        "Pleroma.Upload.Filter.AnonymizeFilename"
      ];
}
```

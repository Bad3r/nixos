{ lib }:
let
  count = predicate: list: lib.length (lib.filter predicate list);
  toPercent =
    numerator: denominator: if denominator == 0 then 0.0 else (numerator * 100.0) / (denominator * 1.0);

  summarizeModules =
    modules:
    let
      total = lib.length modules;
      extracted = count (module: module.status == "ok") modules;
      skipped = count (module: module.status == "skipped") modules;
      failed = count (module: module.status == "error") modules;
    in
    {
      inherit
        total
        extracted
        skipped
        failed
        ;
      extractionRate = toPercent extracted total;
    };

  summarizeNamespaces = namespaceMap: lib.mapAttrs (_: summarizeModules) namespaceMap;

  collectErrors = modules: lib.filter (module: module.status == "error") modules;

  collectSkips = modules: lib.filter (module: module.status == "skipped") modules;

in
{
  inherit
    summarizeModules
    summarizeNamespaces
    collectErrors
    collectSkips
    ;
}

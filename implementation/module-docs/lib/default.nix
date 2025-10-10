{ lib }:
let
  typesLib = import ./types.nix { inherit lib; };
  renderLib = import ./render.nix { inherit lib; } typesLib;
  metricsLib = import ./metrics.nix { inherit lib; };
in
{
  inherit (typesLib)
    extractType
    extractOptionType
    extractSubmodule
    extractDeclarations
    extractConfig
    extractOption
    extractModule
    ;

  inherit (renderLib)
    sanitizeValue
    moduleDocFromEvaluation
    ;

  inherit (metricsLib)
    summarizeModules
    summarizeNamespaces
    collectErrors
    collectSkips
    ;
}

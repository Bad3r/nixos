/*
  Internal: shared Gecko-browser search engines
  Description: Declarative search engine list applied to every Firefox/Floorp/LibreWolf primary profile.
*/

_: {
  search = {
    force = true;
    default = "Google Custom";
    engines = {
      "Google Custom" = {
        name = "Google Custom";
        urls = [
          {
            template = "https://www.google.com/search";
            params = [
              {
                name = "q";
                value = "{searchTerms}";
              }
              {
                name = "hl";
                value = "en";
              }
              {
                name = "gl";
                value = "US";
              }
              {
                name = "pws";
                value = "0";
              }
              {
                name = "safe";
                value = "off";
              }
            ];
          }
        ];
        icon = "https://www.google.com/favicon.ico";
        definedAliases = [ "@g" ];
      };

      Kagi = {
        name = "Kagi";
        icon = "https://kagi.com/favicon-32x32.png";
        urls = [
          { template = "https://kagi.com/search?q={searchTerms}"; }
          {
            template = "https://kagi.com/api/autosuggest?q={searchTerms}";
            type = "application/x-suggestions+json";
          }
        ];
        definedAliases = [ "@k" ];
      };

      "Nix Packages" = {
        name = "Nix Packages";
        urls = [
          { template = "https://search.nixos.org/packages?query={searchTerms}"; }
        ];
        definedAliases = [ "@nix" ];
      };
    };
  };
}

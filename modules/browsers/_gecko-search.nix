/*
  Internal: shared Gecko-browser search configuration
  Description: Search-related enterprise policies and preferences applied to
    Firefox and LibreWolf.
*/

_: {
  policies = {
    SearchEngines = {
      Default = "Google US";
      PreventInstalls = false;
      Remove = [
        "Google"
        "Bing"
        "DuckDuckGo Lite"
        "Searx Belgium"
        "MetaGer"
        "Startpage"
        "Mojeek"
        "YouTube"
        "Wikipedia (en)"
      ];
      Add = [
        {
          Name = "Google US";
          Description = "Google search with English, US, no personalization, and SafeSearch off.";
          Alias = "@g";
          Method = "GET";
          URLTemplate = "https://www.google.com/search?q={searchTerms}&hl=en&persist_hl=1&gl=US&persist_gl=1&pws=0&safe=off";
          IconURL = "https://www.google.com/favicon.ico";
        }
        # {
        #   Name = "Kagi";
        #   Description = "Premium private search engine.";
        #   Alias = "@k";
        #   Method = "GET";
        #   URLTemplate = "https://kagi.com/search?q={searchTerms}";
        #   SuggestURLTemplate = "https://kagi.com/api/autosuggest?q={searchTerms}";
        #   IconURL = "https://kagi.com/favicon-32x32.png";
        # }
        {
          Name = "YouTube US";
          Description = "YouTube search with English, US region, and no separate suggest endpoint.";
          Alias = "@yt";
          Method = "GET";
          URLTemplate = "https://www.youtube.com/results?search_query={searchTerms}&hl=en&persist_hl=1&gl=US&persist_gl=1";
          IconURL = "https://www.youtube.com/s/desktop/b232f2cf/img/favicon.ico";
        }
        {
          Name = "Yandex";
          Description = "Yandex search with English localization, US region, and filtering disabled.";
          Alias = "@y";
          Method = "GET";
          URLTemplate = "https://yandex.com/search/?text={searchTerms}&lang=en&lr=84&filter=none";
          IconURL = "https://yandex.com/favicon.ico";
        }
        {
          Name = "Nix Packages";
          Description = "Search packages on search.nixos.org.";
          Alias = "@nix";
          Method = "GET";
          URLTemplate = "https://search.nixos.org/packages?query={searchTerms}";
          IconURL = "https://search.nixos.org/favicon-96x96.png";
        }
        {
          Name = "Raindrop.io";
          Description = "Search the Raindrop.io vault.";
          Alias = "@rd";
          Method = "GET";
          URLTemplate = "https://app.raindrop.io/my/0/{searchTerms}";
          IconURL = "https://app.raindrop.io/assets/icon_raw.0c4defdf0f566d97f952a81a3bf82d46.svg";
        }
      ];
    };
  };

  settings = {
    "accessibility.typeaheadfind" = false; # Conflicts with Tridactyl.
    "accessibility.typeaheadfind.flashBar" = 0;

    "browser.newtabpage.activity-stream.showSearch" = false;
    "browser.search.serpEventTelemetryCategorization.regionEnabled" = false;

    # Disable Firefox Suggest (quicksuggest); keep engine suggestions working.
    "browser.urlbar.quicksuggest.enabled" = false;
    "browser.urlbar.suggest.quicksuggest.all" = false;
    "browser.urlbar.suggest.quicksuggest.nonsponsored" = false;
    "browser.urlbar.suggest.quicksuggest.sponsored" = false;
  };
}

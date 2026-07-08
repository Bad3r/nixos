/*
  Internal: shared managed-policy payloads for Chromium-family browsers
  Description: Extension force-install list and default-search-provider
  policy shared verbatim by google-chrome and ungoogled-chromium so the
  two browsers stay symmetric. Imported via a relative path; the leading
  underscore keeps this file out of module auto-discovery.
*/
{
  managedExtensionSettings = {
    # uBlock Origin Lite
    "ddkjiahejlhfcafbddmgiahcphecmpfh" = {
      installation_mode = "force_installed";
      update_url = "https://clients2.google.com/service/update2/crx";
    };
    # 1Password - Password Manager
    "aeblfdkhhhdcdjpifhhbdiojplfjncoa" = {
      installation_mode = "force_installed";
      update_url = "https://clients2.google.com/service/update2/crx";
    };
  };

  managedDefaultSearchProvider = {
    DefaultSearchProviderEnabled = true;
    DefaultSearchProviderName = "Google";
    DefaultSearchProviderKeyword = "google.com";
    DefaultSearchProviderSearchURL = "https://www.google.com/search?q={searchTerms}&hl=en&gl=US&pws=0&safe=off";
    DefaultSearchProviderSuggestURL = "https://www.google.com/complete/search?hl=en&gl=US&client=chrome&q={searchTerms}";
    DefaultSearchProviderIconURL = "https://www.google.com/favicon.ico";
    DefaultSearchProviderEncodings = [ "UTF-8" ];
  };
}

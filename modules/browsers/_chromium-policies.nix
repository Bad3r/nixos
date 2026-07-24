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
    DefaultSearchProviderName = "Kagi";
    DefaultSearchProviderKeyword = "kagi.com";
    DefaultSearchProviderSearchURL = "https://kagi.com/search?q={searchTerms}";
    DefaultSearchProviderSuggestURL = "https://kagi.com/api/autosuggest?q={searchTerms}";
    DefaultSearchProviderIconURL = "https://kagi.com/favicon-32x32.png";
    DefaultSearchProviderEncodings = [ "UTF-8" ];
  };
}

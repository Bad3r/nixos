# Shared Mullvad DNS-over-HTTPS resolver URL for the Gecko and Chromium
# policy modules. doh. is a SAN alias of Mullvad's documented
# adblock.dns.mullvad.net on the same resolver; the dns., dot. and
# public-resolver. names are SNI-reset on the fleet's ISP, so do not restore
# the documented name.
"https://adblock.doh.mullvad.net/dns-query"

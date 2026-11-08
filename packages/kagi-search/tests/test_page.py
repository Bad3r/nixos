# Copyright (c) 2026 Bad3r
"""Hits, empty answers, and URL hosts of Kagi's results page."""

import unittest

from kagi_search.page import (
    Hit,
    UnrecognizedPageError,
    filter_hits,
    host_of,
    kagi_query,
    parse_page,
)

RESULTS = """<!doctype html><html><head><title>nixos - Kagi Search</title>
<script>var x = '<div class="search-result">';</script></head><body>
<a href="https://account.kagi.com/settings">Account</a>
<div class="search-result">
  <h3><a class="__sri_title_link _0_sri_title_link"
    href="https://nixos.org/">NixOS &amp; Nix</a></h3>
  <div class="__sri-body"><div class="__sri-desc">Declarative <b>builds</b> &#x2014; reproducible.
    <a class="_0_summarize_page summarize-link" href="/summarizer?url=x">Summarize</a>
  </div></div>
  <img src="x.png"><br/>
</div>
<div class="search-result">
  <h3><a class="__sri_title_link" href="/proxy?u=1">Internal</a></h3>
</div>
<div class="search-result">
  <h3><a class="__sri_title_link" href="https://evil.example\\@nixos.org/">Spoof</a></h3>
</div>
<div class="sr-group">
  <div class="__srgi">
    <div class="__srgi-title"><a
      href="https://wiki.nixos.org/wiki/Flakes">Flakes - NixOS Wiki</a></div>
    <div class="__sri-desc">Flakes are...</div>
  </div>
  <div class="__srgi">
    <div class="__srgi-title"><a href="https://nixos.org/">NixOS &amp; Nix</a></div>
  </div>
</div>
</body></html>"""

NO_RESULTS = """<html><head><title>"x" site:example.com - Kagi Search</title></head><body>
<a href="https://account.kagi.com/settings">Account</a>
<div class="error-content"><h1>We haven&#39;t found anything.</h1>
<ul class="no-results-options"><li><a href="/html/search?q=x">x</a></li></ul></div>
</body></html>"""

FILTER_HITS = [
    Hit("a", "https://nixos.org/x", ""),
    Hit("b", "https://wiki.nixos.org/y", ""),
    Hit("c", "https://notnixos.org/", ""),
    Hit("d", "https://evil.example\\@nixos.org/", ""),
]


class ParsePageTest(unittest.TestCase):
    """Hits and page kinds read from the results HTML."""

    def test_hits_in_page_order_each_url_once(self) -> None:
        """Plain and grouped hits keep page order; unsafe and repeated URLs drop."""
        self.assertEqual(
            parse_page(RESULTS),
            [
                Hit("NixOS & Nix", "https://nixos.org/", "Declarative builds — reproducible."),
                Hit("Flakes - NixOS Wiki", "https://wiki.nixos.org/wiki/Flakes", "Flakes are..."),
            ],
        )

    def test_no_results_answer_is_empty_despite_account_links(self) -> None:
        """Kagi's no-results page yields no hits."""
        self.assertEqual(parse_page(NO_RESULTS), [])

    def test_containers_without_title_links_are_unrecognized(self) -> None:
        """Result containers whose title links changed raise instead of reading as no results."""
        page = (
            '<title>nixos - Kagi Search</title><div class="search-result">'
            '<h3><a class="__sri_link_renamed" href="https://nixos.org/">NixOS</a></h3></div>'
        )
        with self.assertRaises(UnrecognizedPageError):
            parse_page(page)

    def test_a_foreign_page_is_unrecognized_with_its_title(self) -> None:
        """A page without result markup raises with its title."""
        with self.assertRaisesRegex(UnrecognizedPageError, r"title: Maintenance\)"):
            parse_page("<title>Maintenance</title><p>down</p>")


class HostTest(unittest.TestCase):
    """Hosts of plain and ambiguous URLs."""

    def test_plain_hosts(self) -> None:
        """The host is lowercased without port, path, query, or fragment."""
        self.assertEqual(host_of("https://Wiki.NixOS.org:8443/x?y#z"), "wiki.nixos.org")
        self.assertEqual(host_of("http://example.com"), "example.com")

    def test_ambiguous_urls_have_no_host(self) -> None:
        """Backslashes, userinfo, blanks, other schemes, and relative URLs have none."""
        for url in (
            "https://evil.example\\@nixos.org/",
            "https://user@nixos.org/",
            "https://evil.example%2f@nixos.org/",
            "https://nixos.org /",
            "ftp://nixos.org/",
            "/relative",
        ):
            with self.subTest(url=url):
                self.assertIsNone(host_of(url))


class FilterTest(unittest.TestCase):
    """Domain allow and block lists, and the site: narrowing."""

    def test_allowed_domains_keep_hosts_and_subdomains(self) -> None:
        """An allowed domain keeps itself and its subdomains."""
        kept = filter_hits(FILTER_HITS, allowed=["nixos.org"])
        self.assertEqual([h.title for h in kept], ["a", "b"])

    def test_blocked_domains_drop_hosts_and_subdomains(self) -> None:
        """A blocked domain, even given as a URL, drops itself and its subdomains."""
        kept = filter_hits(FILTER_HITS, blocked=["https://wiki.nixos.org/"])
        self.assertEqual([h.title for h in kept], ["a", "c"])

    def test_one_allowed_domain_narrows_the_query(self) -> None:
        """Only a single allowed domain adds site: to the query."""
        self.assertEqual(kagi_query("flakes", ["wiki.nixos.org"]), "flakes site:wiki.nixos.org")
        self.assertEqual(kagi_query("flakes", ["a.org", "b.org"]), "flakes")

# Pentesting Toolkit: Browser & API Automation

[Back to Pentesting Toolkit](../toolkit.md)

## Browser & API Automation

- playwright
  - run..: `playwright codegen $url`
  - Repo.: <https://github.com/microsoft/playwright>
  - Docs.: <https://playwright.dev/docs/intro>
  - Desc.: Cross-browser automation CLI (`playwright test`, `playwright open`, `playwright codegen`) backed by Chromium, Firefox, and WebKit; useful for fuzzing, headless recon, and recording interaction scripts.
- selenium
  - run..: `selenium-side-runner $tests`
  - Repo.: <https://github.com/SeleniumHQ/selenium>
  - Docs.: <https://www.selenium.dev/documentation/>
  - Desc.: Long-running browser automation framework.
- httpie
  - run..: `http GET $url`
  - Repo.: <https://github.com/httpie/cli>
  - Docs.: <https://httpie.io/docs>
  - Desc.: User-friendly HTTP CLI used in recon and exploitation.
- curlie
  - run..: `curlie $url`
  - Repo.: <https://github.com/rs/curlie>
  - Docs.: <https://github.com/rs/curlie#readme>
  - Desc.: HTTPie-style frontend over curl.
- curl
  - run..: `curl -sS $url`
  - Repo.: <https://github.com/curl/curl>
  - Docs.: <https://curl.se/docs/>
  - Desc.: Universal HTTP client used everywhere in recon and exploitation.
- xh
  - run..: `xh GET $url`
  - Repo.: <https://github.com/ducaale/xh>
  - Docs.: <https://github.com/ducaale/xh#readme>
  - Desc.: Rust HTTPie clone for ergonomic HTTP requests.
- wget
  - run..: `wget $url`
  - Repo.: <https://git.savannah.gnu.org/cgit/wget.git>
  - Docs.: <https://www.gnu.org/software/wget/manual/>
  - Desc.: Bulk HTTP downloader used in recon.
- htmlq
  - run..: `htmlq -f page.html '.selector'`
  - Repo.: <https://github.com/mgdm/htmlq>
  - Docs.: <https://github.com/mgdm/htmlq#readme>
  - Desc.: CSS-selector HTML parser for scraping recon output.
- lychee
  - run..: `lychee --no-progress $url`
  - Repo.: <https://github.com/lycheeverse/lychee>
  - Docs.: <https://lychee.cli.rs/guides/cli/>
  - Desc.: Fast asynchronous link checker for URLs, mail addresses, local files, and website content.
- yaak
  - run..: `yaak`
  - Repo.: <https://github.com/mountain-loop/yaak>
  - Docs.: <https://yaak.app/docs>
  - Desc.: API client useful during web service testing.

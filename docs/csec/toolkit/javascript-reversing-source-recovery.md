# Pentesting Toolkit: JavaScript Reversing & Source Recovery

[Back to Pentesting Toolkit](../toolkit.md)

## JavaScript Reversing & Source Recovery

- asar
  - run..: `asar extract $app/resources/app.asar out/`
  - Repo.: <https://github.com/electron/asar>
  - Docs.: <https://github.com/electron/asar#readme>
  - Desc.: Lists, extracts, and repacks Electron `app.asar` archives to reach an app's bundled JavaScript.
- source-map-explorer
  - run..: `source-map-explorer bundle.js bundle.js.map`
  - Repo.: <https://github.com/danvk/source-map-explorer>
  - Docs.: <https://github.com/danvk/source-map-explorer#readme>
  - Desc.: Visualizes JavaScript bundles using source maps.
- sourcemapper
  - run..: `sourcemapper -url $url -output dir`
  - Repo.: <https://github.com/denandz/sourcemapper>
  - Docs.: <https://github.com/denandz/sourcemapper#readme>
  - Desc.: Reconstructs original sources from production source maps.
- synchrony
  - run..: `synchrony bundle.js`
  - Repo.: <https://github.com/relative/synchrony>
  - Docs.: <https://github.com/relative/synchrony#readme>
  - Desc.: JavaScript deobfuscator targeting common obfuscators.
- wakaru
  - run..: `wakaru bundle.js -o out/`
  - Repo.: <https://github.com/pionxzh/wakaru>
  - Docs.: <https://wakaru.netlify.app/>
  - Desc.: JavaScript reverse-engineering toolkit (deminify, deobfuscate).
- webcrack
  - run..: `webcrack bundle.js -o out/`
  - Repo.: <https://github.com/j4k0xb/webcrack>
  - Docs.: <https://github.com/j4k0xb/webcrack#readme>
  - Desc.: JavaScript bundle unpacker and deobfuscator.

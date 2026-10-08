# Pentesting Toolkit: QR & Encoded Payload Handling

[Back to Pentesting Toolkit](../toolkit.md)

## QR & Encoded Payload Handling

- qrencode
  - run..: `qrencode -o out.png "$payload"`
  - Repo.: <https://github.com/fukuchi/libqrencode>
  - Docs.: <https://fukuchi.org/works/qrencode/>
  - Desc.: Generates QR codes; useful for crafting CTF or MFA enrollment payloads.
- zbar
  - run..: `zbarimg $image`
  - Repo.: <https://github.com/mchehab/zbar>
  - Docs.: <https://github.com/mchehab/zbar#readme>
  - Desc.: Decodes QR and 1D barcodes from images and webcams.

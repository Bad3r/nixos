# Pentesting Toolkit: Forensics, Recovery & Imaging

[Back to Pentesting Toolkit](../toolkit.md)

## Forensics, Recovery & Imaging

- ddrescue
  - run..: `ddrescue $src $dst log.txt`
  - Repo.: <https://www.gnu.org/software/ddrescue/>
  - Docs.: <https://www.gnu.org/software/ddrescue/manual/ddrescue_manual.html>
  - Desc.: Block-level recovery from failing media; standard forensic imager.
- ent
  - run..: `ent $file`
  - Repo.: <https://www.fourmilab.ch/random/>
  - Docs.: <https://www.fourmilab.ch/random/>
  - Desc.: Statistical randomness tests for entropy and crypto-quality analysis.
- exiftool
  - run..: `exiftool $file`
  - Repo.: <https://github.com/exiftool/exiftool>
  - Docs.: <https://exiftool.org/>
  - Desc.: EXIF and metadata reader/editor for images, documents, and binaries.
- file
  - run..: `file $path`
  - Repo.: <https://github.com/file/file>
  - Docs.: <https://www.darwinsys.com/file/>
  - Desc.: Magic-byte file type identification.
- foremost
  - run..: `foremost -i $image -o output/`
  - Repo.: <https://foremost.sourceforge.net/>
  - Docs.: <https://foremost.sourceforge.net/>
  - Desc.: Header-based file carving from disk images.
- normcap
  - run..: `normcap`
  - Repo.: <https://github.com/dynobo/normcap>
  - Docs.: <https://dynobo.github.io/normcap/>
  - Desc.: Screen OCR for extracting text from CTF artifacts and screenshots.
- testdisk
  - run..: `testdisk`
  - Repo.: <https://www.cgsecurity.org/wiki/TestDisk>
  - Docs.: <https://www.cgsecurity.org/wiki/TestDisk_Documentation>
  - Desc.: Partition table and filesystem recovery.
- ventoy-full
  - run..: `Ventoy2Disk.sh -i /dev/sdX`
  - Repo.: <https://github.com/ventoy/Ventoy>
  - Docs.: <https://www.ventoy.net/en/doc_start.html>
  - Desc.: Multi-ISO bootable USB builder for forensic and live-response media.
- xxd
  - run..: `xxd $file`
  - Repo.: <https://github.com/vim/vim>
  - Docs.: <https://linux.die.net/man/1/xxd>
  - Desc.: Hex dump and reverse hex viewer.

# Pentesting Toolkit: Credential Attacks & Wordlists

[Back to Pentesting Toolkit](../toolkit.md)

## Credential Attacks & Wordlists

- cewl
  - run..: `cewl $url`
  - Repo.: <https://github.com/digininja/CeWL>
  - Docs.: <https://github.com/digininja/CeWL#readme>
  - Desc.: Custom wordlist generator that scrapes target sites.
- hashcat
  - run..: `hashcat -m $mode hashes.txt wordlist.txt`
  - Repo.: <https://github.com/hashcat/hashcat>
  - Docs.: <https://hashcat.net/wiki/>
  - Desc.: GPU-accelerated password hash cracker.
- hydra
  - run..: `hydra -L users.txt -P passwords.txt $target $service`
  - Repo.: <https://github.com/vanhauser-thc/thc-hydra>
  - Docs.: <https://github.com/vanhauser-thc/thc-hydra#readme>
  - Desc.: Parallelized network login brute forcer.
- john
  - run..: `john --wordlist=$wordlist hashes.txt`
  - Repo.: <https://github.com/openwall/john>
  - Docs.: <https://www.openwall.com/john/doc/>
  - Desc.: John the Ripper CPU-focused password cracker.
- seclists
  - run..: `ls $(nix eval --raw nixpkgs#seclists)/share/seclists`
  - Repo.: <https://github.com/danielmiessler/SecLists>
  - Docs.: <https://github.com/danielmiessler/SecLists#readme>
  - Desc.: Curated wordlist collection (passwords, payloads, fuzzing data).

Reference list trees shipped by the entries above (resolve with `nix eval --raw nixpkgs#<pkg>` and concatenate with the noted suffix):

- `seclists` -> `share/seclists/`
- `nmap` -> `share/nmap/nselib/data/` (`passwords.lst`, `usernames.lst`, `snmpcommunities.lst`, `http-sql-errors.lst`, `drupal-modules.lst`, `oracle-default-accounts.lst`, `vhosts-{full,default}.lst`, `wp-{plugins,themes}.lst`, `http-web-files-extensions.lst`)
- `john` -> `share/john/` (`password.lst`, `*.chr`, `rules/`)
- `hashcat` -> `share/doc/hashcat/` (`rules/`, `masks/`, `charsets/`)

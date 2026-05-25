# Useful Commands

This document contains a collection of useful commands that might not be directly related to NixOS or this repository, but are handy to have around.

## General CLI

### less

Open a file and immediately scroll to the bottom (end of file):

```bash
fp="file.txt"
less +G $fp
```

### sponge (moreutils)

Read standard input and write it to a file, soaking up all input before opening the output file (useful for reading from and writing to the same file in a pipeline).
If no file is specified, it writes to standard output:

```bash
fp="file.txt"
cat $fp | sort | sponge $fp

```

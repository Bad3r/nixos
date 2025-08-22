## Generating the Pleroma config

The `pleroma_ctl` CLI utility will prompt you some questions and it will generate an initial config file. This is an example of usage

```programlisting
$ mkdir tmp-pleroma
$ cd tmp-pleroma
$ nix-shell -p pleroma-otp
$ pleroma_ctl instance gen --output config.exs --output-psql setup.psql
```

The `config.exs` file can be further customized following the instructions on the [upstream documentation](https://docs-develop.pleroma.social/backend/configuration/cheatsheet/). Many refinements can be applied also after the service is running.

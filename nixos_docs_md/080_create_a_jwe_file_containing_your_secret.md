## Create a JWE file containing your secret

The first step is to embed your secret in a [JWE](https://en.wikipedia.org/wiki/JSON_Web_Encryption) file. JWE files have to be created through the clevis command line. 3 types of policies are supported:

1.  TPM policies

Secrets are pinned against the presence of a TPM2 device, for example:

```programlisting
echo -n hi | clevis encrypt tpm2 '{}' > hi.jwe
```

2.  Tang policies

Secrets are pinned against the presence of a Tang server, for example:

```programlisting
echo -n hi | clevis encrypt tang '{"url": "http://tang.local"}' > hi.jwe
```

3.  Shamir Secret Sharing

Using Shamir’s Secret Sharing ([sss](https://en.wikipedia.org/wiki/Shamir%27s_secret_sharing)), secrets are pinned using a combination of the two preceding policies. For example:

```programlisting
echo -n hi | clevis encrypt sss \
'{"t": 2, "pins": {"tpm2": {"pcr_ids": "0"}, "tang": {"url": "http://tang.local"}}}' \
> hi.jwe
```

For more complete documentation on how to generate a secret with clevis, see the [clevis documentation](https://github.com/latchset/clevis).

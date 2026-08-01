# Look up cybersecurity and software engineering terms

This glossary defines acronyms and concepts used in the repository's
cybersecurity and software engineering documentation. Keep entries in
alphabetical order by term and use the same fields for each entry: definition,
example, security note, and references.

## TOFU (trust on first use)

### Definition

TOFU is a trust model in which a client accepts and records a server's
identity key on the first connection without prior out-of-band verification. On
later connections, the client compares the presented key with the recorded key
and reports a mismatch.

### Example

When SSH connects to an unfamiliar server, it may display a prompt such as:

```text
The authenticity of host 'server (192.168.1.10)' can't be established.
ED25519 key fingerprint is SHA256:...
Are you sure you want to continue connecting (yes/no)?
```

After accepting the key, SSH records it in a known-hosts file, usually
`~/.ssh/known_hosts` or the path configured by `UserKnownHostsFile`. Confirm
the fingerprint through a trusted out-of-band channel before accepting it when
that channel is available.

### Security note

TOFU helps detect a changed host key after the initial connection, but it does
not prove that the first key was authentic. An attacker who intercepts the
initial connection can establish the key that the client records, creating a
man-in-the-middle (MITM) risk. A later key change can also result from a
legitimate server reinstallation or key rotation, so investigate the cause
before accepting a replacement key.

### References

- [RFC 4253, section 8: Diffie-Hellman key exchange](https://datatracker.ietf.org/doc/html/rfc4253#section-8)
- [OpenSSH `ssh(1)` manual, host-key checking](https://man.openbsd.org/ssh#HOST_KEY_AUTHENTICATION)
- [OpenSSH `ssh_config(5)` manual, `StrictHostKeyChecking`](https://man.openbsd.org/ssh_config#StrictHostKeyChecking)

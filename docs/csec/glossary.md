# Look up cybersecurity and software engineering terms

This glossary defines acronyms and concepts used in the repository's
cybersecurity and software engineering documentation. Keep entries in
alphabetical order by term and use the same fields for each entry: definition,
example, security note, and references.

## Contents

- [Masquerading](#masquerading)
- [TOFU (trust on first use)](#tofu-trust-on-first-use)

## Masquerading

### Definition

Masquerading is an adversary technique that manipulates the name, location,
metadata, appearance, or other identifying features of an object so that a
malicious or suspicious artifact appears legitimate or benign to users or
security tools. MITRE ATT&CK identifies it as technique `T1036`; ATT&CK v19 and
later assign it to the Stealth tactic, while v18 and earlier classified it under
Defense Evasion.

### Example

Right-to-left override (RTLO or RLO) is sub-technique `T1036.002`. The Unicode
control character `U+202E` reverses the display order of the text that follows
it. A filename whose logical name is:

```text
photo_high_re\u202Egnp.js
```

may be displayed as `photo_high_resj.png`, causing a JavaScript file to appear
to have a `.png` extension. The backslash notation above represents the
non-printing character and is used to keep the example visible in source.

### Security note

Do not determine a file's type from its displayed name alone. Inspect the
underlying file type, signature, and complete filename, and make Unicode
formatting controls visible during triage. Detection and prevention controls
should flag or restrict unexpected `U+202E` characters in filenames, especially
when the file is downloaded, attached to an email, or about to execute.
The RTLO sub-technique can be detected by inspecting filenames for the actual
`U+202E` character and, in logs or serialized telemetry, separately accounting
for escaped (`\u202E`), labeled (`[U+202E]`), and percent-encoded (`%E2%80%AE`)
representations. These representations are not interchangeable stored values;
search each according to the field's encoding.

### References

- [MITRE ATT&CK T1036: Masquerading](https://attack.mitre.org/techniques/T1036/)
- [MITRE ATT&CK v18 T1036: Masquerading](https://attack.mitre.org/versions/v18/techniques/T1036/)
- [MITRE ATT&CK T1036.002: Right-to-Left Override](https://attack.mitre.org/techniques/T1036/002/)

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

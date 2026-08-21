# Look up cybersecurity and software engineering terms

This glossary defines acronyms and concepts used in the repository's
cybersecurity and software engineering documentation. Keep entries in
alphabetical order by term and use the same fields for each entry: definition,
example, security note, and references. Add every new entry to the `Contents`
list below, which is maintained by hand.

## Contents

- [Baseline deviation](#baseline-deviation)
- [DIKW pyramid](#dikw-pyramid)
- [Dwell time](#dwell-time)
- [Fuzzy hashing](#fuzzy-hashing)
- [Linked data](#linked-data)
- [OODA loop](#ooda-loop)
- [Pyramid of pain](#pyramid-of-pain)
- [Threat hunting](#threat-hunting)
- [TOFU (trust on first use)](#tofu-trust-on-first-use)

## Baseline deviation

### Definition

A baseline deviation is an observed difference between expected activity and
actual user, host, network, or application behavior. In threat hunting,
observations of baseline deviations are used to develop hypotheses that guide
further investigation.

### Example

A privileged account authenticating from a new host outside its normal hours is
a baseline deviation.

### Security note

A baseline deviation is an investigative signal, not proof of compromise.
Validate it against approved changes, known administrative activity, and the
exercise scope before classifying it as malicious.

### References

- [NIST CSRC glossary: Behavioral Anomaly Detection](https://csrc.nist.gov/glossary/term/behavioral_anomaly_detection)
- [CISA Red Team Shares Key Findings to Improve Monitoring and Hardening of Networks](https://www.cisa.gov/news-events/cybersecurity-advisories/aa23-059a)

## DIKW pyramid

### Definition

The DIKW pyramid is a conceptual hierarchy describing how raw data can be
organized into information, interpreted as knowledge, and applied with
judgment as wisdom. The layers are commonly summarized as data, information,
knowledge, and wisdom.

### Example

Individual authentication events are data. Grouping them by account, source,
and time produces information about login patterns. Recognizing an unusual
sequence as possible credential abuse produces knowledge, while choosing a
proportionate containment action based on business impact and available
evidence applies that knowledge as wisdom.

### Security note

The DIKW pyramid is a reasoning aid, not a mandatory or strictly linear
process. Accurate conclusions still depend on data quality, context, and
analyst judgment, and more abstract layers do not automatically make a
conclusion more reliable.

### References

- [The wisdom hierarchy: representations of the DIKW hierarchy](https://doi.org/10.1177/0165551506070706)

## Dwell time

### Definition

Dwell time is the interval between an adversary's initial compromise of an
environment and the detection of that compromise.

### Example

An intrusion that begins with a phishing-delivered implant on 2026-03-01 and is
detected by an endpoint alert on 2026-04-12 has a dwell time of 42 days.

### Security note

Dwell time is measured from the earliest compromise that forensic evidence can
establish, not from the first alert. Log retention bounds how far back that
reconstruction reaches, so an intrusion that outlives the retention window is
reported with a dwell time biased low. Record the evidence window alongside the
figure, and treat published cross-organization medians as context rather than a
target.

### References

- [M-Trends 2026](https://cloud.google.com/blog/topics/threat-intelligence/m-trends-2026/)

## Fuzzy hashing

### Definition

Fuzzy hashing is a similarity-preserving technique that produces a digest
designed to estimate how similar two inputs are, even when they are not
byte-for-byte identical. Unlike cryptographic hashes, which are designed so
small input changes produce unrelated digests, fuzzy hashes provide a
similarity score for approximate matching.

### Example

An analyst computes a fuzzy hash for a suspicious executable and compares it
with a reference set. A high similarity score can prioritize a sample for
investigation even when its cryptographic hash differs because of a small
change.

### Security note

A fuzzy-hash similarity score is a triage signal, not proof that files are
identical, share authorship, or are malicious. Scores and detection limits
vary by algorithm, file type, input size, and threshold, and an adversary may
be able to manipulate the input to evade similarity matching. Use
cryptographic hashes for exact integrity checks and combine fuzzy matches with
static, behavioral, and provenance evidence.

### References

- [NIST SP 800-168, Approximate Matching: Definition and Terminology](https://csrc.nist.gov/pubs/sp/800/168/final)
- [Carnegie Mellon Software Engineering Institute: Fuzzy Hashing Techniques in Applied Malware Analysis](https://insights.sei.cmu.edu/blog/fuzzy-hashing-techniques-in-applied-malware-analysis/)

## Linked data

### Definition

Linked data is structured, machine-readable data in which identifiable entities
are connected by explicit relationships, allowing information from different
sources to be combined and analyzed as a graph.

### Example

A security investigation links a user, workstation, authentication event, and
destination domain to trace a suspicious login across related records instead
of reviewing each record in isolation.

### Security note

Entity-resolution errors can create false links or hide real ones. Verify
identifiers, timestamps, and source provenance before treating a graph
relationship as evidence.

### References

- [W3C: Linked Data](https://www.w3.org/DesignIssues/LinkedData.html)

## OODA loop

### Definition

The OODA loop is an iterative decision-making cycle of Observe, Orient,
Decide, and Act. It describes how a person or team gathers observations,
interprets them in context, selects a response, and acts before reassessing
the resulting situation.

### Example

A security operations team observes a suspicious PowerShell alert and collects
the process, user, host, and network context. The team orients by comparing the
activity with the host's role, known changes, and threat intelligence, decides
to isolate the host while preserving evidence, and acts by applying the
containment control. The resulting telemetry starts the next loop.

### Security note

A fast loop without sound orientation can accelerate an incorrect response.
Challenge assumptions, preserve relevant evidence, and confirm that
containment or recovery actions are authorized before acting.

### References

- [NIST CSRC glossary: OODA](https://csrc.nist.gov/glossary/term/ooda)

## Pyramid of pain

### Definition

The Pyramid of Pain is a threat-hunting model that ranks adversary indicators
by how difficult and costly they are for an attacker to change after
detection. From lower to higher levels, it commonly considers hash values, IP
addresses, domain names, network and host artifacts, tools, and tactics,
techniques, and procedures (TTPs).

### Example

A hunt based only on a malware hash may miss a rebuilt sample, while a hunt for
the associated behavior, such as an encoded PowerShell download followed by a
scheduled-task persistence change, can remain useful after the file changes.

### Security note

Lower-level indicators are useful for fast triage but are often easy to change.
Higher-level behavior is usually more durable but less unique, so validate it
with context, baselines, and multiple data sources before treating it as
malicious.

### References

- [A Framework for Cyber Threat Hunting Part 1: The Pyramid of Pain](https://www.threathunting.net/files/A%20Framework%20for%20Cyber%20Threat%20Hunting%20Part%201_%20The%20Pyramid%20of%20Pain%20_%20Sqrrl.pdf)

## Threat hunting

### Definition

Threat hunting is the human-driven activity of proactively and iteratively
searching through the organization's environment (network, endpoints, and
applications) for signs of compromise to shorten the dwell time and minimize
the breach impact for the organization.

### Example

An analyst hypothesizes that an adversary is using scheduled tasks for
persistence, queries endpoint telemetry for task creations that launch encoded
interpreters, and reviews the results against the host baseline instead of
waiting for an alert to fire.

### Security note

A hunt that finds nothing is not evidence of a clean environment. It bounds only
what the queried telemetry could have shown, so record the hypothesis, the data
sources searched, and their retention window to keep a negative result
interpretable later. Promote a confirmed hunt finding into a durable detection
rather than leaving it as a one-off investigation.

### References

- [NIST SP 800-53 Rev. 5, control RA-10: Threat Hunting](https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final)

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

- [RFC 4251, section 4.1: Host Keys](https://datatracker.ietf.org/doc/html/rfc4251#section-4.1)
- [OpenSSH `ssh(1)` manual, verifying host keys](https://man.openbsd.org/ssh#VERIFYING_HOST_KEYS)
- [OpenSSH `ssh_config(5)` manual, `StrictHostKeyChecking`](https://man.openbsd.org/ssh_config#StrictHostKeyChecking)

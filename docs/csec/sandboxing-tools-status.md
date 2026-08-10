# Evaluate malware sandboxing options

This page records the status of open-source and hosted malware sandboxing
options reviewed on 2026-08. It focuses on file, URL, document, and email
detonation for malware analysis. General-purpose process isolation tools are
listed separately because they do not provide the same telemetry or containment
boundary as a disposable virtual machine.

The original Cuckoo 2 project is retired. `CAPE` is the closest active,
self-hosted replacement for the Cuckoo workflow. `DRAKVUF` is the stronger
option when agentless virtual-machine introspection matters. `Assemblyline`
provides the triage and orchestration layer around a detonation backend.
`ANY.RUN` and `Joe Sandbox` provide managed web-based alternatives with faster
deployment, but they require careful review of sample privacy, data residency,
commercial terms, and API limits.

## Compare the current options

| Tool                                 | Category                               | Status                                                                                                | Best fit                                         |
| ------------------------------------ | -------------------------------------- | ----------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| Original Cuckoo 2                    | Self-hosted VM detonation              | Archived and read-only; latest 2.0 release is from 2018                                               | Legacy maintenance only                          |
| Cuckoo3                              | Self-hosted VM detonation              | Open-source revival, but still marked non-production-ready and apparently dormant since December 2025 | Evaluation and migration research                |
| CAPE                                 | Self-hosted VM detonation              | Active rolling development through August 2026; no formal GitHub releases                             | Current Cuckoo-style Windows analysis            |
| DRAKVUF                              | Agentless VMI                          | Active engine and automated builds through August 2026                                                | Stealthier, agentless behavioral analysis        |
| Assemblyline 4                       | Triage and orchestration               | Stable 4.7.4.stable6 and active 4.7.5 development line                                                | SOC-scale file triage around analysis services   |
| PANDA                                | Whole-system research                  | Active QEMU record/replay and plugin platform; tagged releases through June 2026                      | Custom instrumentation and replay research       |
| ANY.RUN                              | Hosted interactive sandbox             | Active commercial SaaS with free public-oriented and paid private plans                               | Fast analyst-driven investigation                |
| Joe Sandbox Cloud                    | Hosted deep-analysis service           | Active commercial SaaS; Cloud upgraded to v44 Smoke Quartz in 2026-01                                 | Managed cross-platform analysis and rich reports |
| Sandboxie-Plus, bubblewrap, Firejail | Local application or process isolation | Active projects, but not malware detonation platforms                                                 | Additional local containment                     |

## Retire the original Cuckoo from new deployments

The [original Cuckoo repository](https://github.com/cuckoosandbox/cuckoo) was
archived by its owner on 2021-04-26 and is read-only. Its README states that
the Cuckoo 2.x line is unmaintained, and the [2.0.6 release](https://github.com/cuckoosandbox/cuckoo/releases/tag/2.0.6)
is from 2018.

## Treat Cuckoo3 as evaluation-only

The [Cuckoo3 rewrite](https://github.com/cert-ee/cuckoo3) is the successor line
listed in the table above. Its `main` branch last advanced on 2025-12-18, and
the only newer commits sit on unmerged dependabot branches. Its
[README](https://github.com/cert-ee/cuckoo3/blob/main/README.md) carries the
production-readiness statement recorded in the table above: "This is not a
production ready solution just yet." Re-check both before treating it as a
migration target.

## Use CAPE for a self-hosted Cuckoo-style platform

[`CAPEv2`](https://github.com/kevoreilly/CAPEv2) is the strongest current
option for the workflow historically associated with Cuckoo. It extends the
Cuckoo lineage with behavioral monitoring, API hooking, dropped-file
collection, PCAP, screenshots, memory dumps, automated unpacking, YARA
classification, and malware configuration extraction.

CAPE does not publish normal GitHub Release objects. Its [tags page](https://github.com/kevoreilly/CAPEv2/tags)
reports that there are no releases, so the activity recorded in the table above
comes from its [commit history](https://github.com/kevoreilly/CAPEv2/commits)
instead. Treat the repository as a rolling development stream:

- Review changes before updating because there is no formal upstream release
  boundary to provide that review point.
- The baseline requirement to pin a reviewed commit or release resolves to a
  commit here, since there is no release tag to pin.

The guest, network, and versioning controls that CAPE shares with the other
self-hosted options are listed under [Apply containment requirements to every detonation option](#apply-containment-requirements-to-every-detonation-option).

The [CAPE installation documentation](https://capev2.readthedocs.io/en/latest/)
uses a Linux host with KVM and Windows analysis guests as its reference model.
This is a capable but operationally demanding deployment, not a single-package
replacement for the old Cuckoo appliance pattern.

## Use DRAKVUF for agentless virtual-machine introspection

[`DRAKVUF`](https://github.com/tklengyel/drakvuf) takes a different approach
from CAPE. It performs virtualization-based, agentless black-box analysis with
virtual-machine introspection, so the guest does not require a conventional
analysis agent. The project documents Intel VT-x/EPT requirements and supports
Windows and Linux analysis scenarios.

- [automated builds repository](https://github.com/tklengyel/drakvuf-builds/releases)
- [DRAKVUF Sandbox frontend](https://github.com/CERT-Polska/drakvuf-sandbox/releases)

DRAKVUF is a good fit when the priority is a lower-footprint, agentless view of
guest behavior. It is less suitable than CAPE when the priority is an easy,
well-known analyst workflow. Xen operations, compatible hardware, guest symbol
handling, and frontend integration add significant engineering work.

## Use Assemblyline to orchestrate analysis

[`Assemblyline 4`](https://github.com/CybercentreCanada/assemblyline) is an
open-source malware triage and orchestration platform rather than a direct
Cuckoo replacement. It provides submission, queueing, scoring, service
execution, result storage, web access, and API-driven workflows for large file
volumes.

Assemblyline's [deployment documentation](https://cybercentrecanada.github.io/assemblyline4_docs/installation/deployment/)
treats Cuckoo and CAPE as external sandbox infrastructure. The practical
architecture is therefore Assemblyline for intake and triage, with CAPE or
another detonation backend for dynamic execution. The version line recorded in
the table above comes from the
[Assemblyline release index](https://github.com/CybercentreCanada/assemblyline/releases),
where `v4.7.4.stable6` was published on 2026-07-16 as the latest `stable` tag
and the `dev` tags carry the development line.

## Use PANDA for research instrumentation

[`PANDA`](https://github.com/panda-re/panda) is a whole-system dynamic-analysis
platform built on QEMU. Its record/replay model and plugin architecture make it
valuable for deterministic experiments, custom instrumentation, reverse
engineering research, and studies that need visibility unavailable in a normal
detonation workflow. The currency recorded in the table above comes from its
[release index](https://github.com/panda-re/panda/releases), where `v1.8.85` was
tagged on 2026-06-09.

PANDA is not a turnkey malware-analysis service. Use it beside CAPE or DRAKVUF
when research instrumentation is required, rather than replacing the
submission, reporting, and guest-lifecycle functions of an operational
sandbox.

## Use ANY.RUN for managed interactive analysis

[`ANY.RUN`](https://any.run/) is a hosted interactive malware sandbox. It lets
an analyst interact with a running analysis system, inspect behavior, and
export results rather than waiting for a single automated verdict. The service
currently advertises Windows 7, Windows 10, Windows 11, Linux, Android, and
macOS analysis platforms, along with API, SDK, STIX, MISP, SIEM, TIP, and XDR
integration.

The [current plans page](https://any.run/plans/) lists a free Community plan
with limited functionality and public-oriented analysis, a Hunter plan with
private analysis and additional operating systems, and an Enterprise Suite
with team controls, SSO, higher API capacity, and additional privacy features.
The [privacy documentation](https://any.run/cybersecurity-blog/privacy/)
explains that public tasks and link-shared tasks can expose the submitted
sample and its results. Confirm the selected visibility before uploading an
internal artifact.

ANY.RUN is attractive when analysts need immediate live interaction, current
browser and operating-system presets, threat-intelligence context, or an API
without operating KVM, guest images, and snapshot infrastructure. It is a
hosted commercial service, not an open-source or self-hosted Cuckoo successor.
It also limits customization of the analysis environment compared with a
self-hosted CAPE deployment.

## Use Joe Sandbox Cloud for managed deep analysis

[`Joe Sandbox Cloud`](https://www.joesandbox.com) is another hosted alternative
for automated and analyst-driven malware analysis. Joe Security describes
Cloud as a web service for analyzing files and URLs targeting Windows, macOS,
and Linux. Its current feature set includes live interaction, hypervisor-based
inspection, execution graphs, network analysis, behavior and YARA signatures,
configuration extraction, PCAP, screenshots, memory dumps, ATT&CK context, and
structured report exports. See the [Joe Sandbox technology overview](https://www.joesecurity.org/index.php/joe-sandbox-technology)
and the [Cloud product page](https://joesecurity.org/joe-sandbox-cloud). The
release line recorded in the table above is
[Joe Sandbox v44 Smoke Quartz](https://www.joesecurity.org/blog/4986670706879863609),
published 2026-01-19, which states that the Cloud Basic, Pro, and OEM servers
were upgraded to it.

The free [Cloud Basic](https://www.joesecurity.org/joe-sandbox-cloud#subscriptions)
tier is intended for evaluation, has limited analysis capacity and output, and
makes samples and results public. Paid Cloud Light, Cloud Pro, and Cloud
Enterprise tiers provide private analysis, with higher tiers adding API,
integration, team, or single-tenant capabilities.

Joe Sandbox is a strong managed option when broad report output, cross-platform
analysis, phishing and email workflows, or commercial integrations matter more
than owning the sandbox infrastructure. It remains a hosted commercial
alternative, not an open-source replacement for CAPE or DRAKVUF.

## Add local isolation as a supplementary layer

These projects are useful as additional containment layers for ordinary
applications and local analysis helpers, but they do not provide a full
malware-detonation environment:

- [`Sandboxie-Plus`](https://github.com/sandboxie-plus/Sandboxie/releases)
  provides Windows application isolation.
- [`bubblewrap`](https://github.com/containers/bubblewrap/releases)
  provides unprivileged Linux namespace isolation.
- [`Firejail`](https://github.com/netblue30/firejail/releases)
  provides Linux namespace and seccomp-based application confinement. It is a
  local process-isolation helper, not a hypervisor boundary.

## Apply containment requirements to every detonation option

> **Warning:** A sandbox result is not evidence that the host is safe. Treat
> every sample as hostile and design for an escape attempt, network abuse, data
> destruction, and credential theft.

These requirements are prerequisites for detonating live samples, not follow-up
work. The local isolation tools in the previous section are out of scope because
they are not detonation platforms.

Apply these to every detonation option above, self-hosted or hosted:

- Never expose credentials, tokens, SSH agents, or mounted shares belonging to
  any system outside the analysis environment to an analysis guest.
- Keep every copy of a sample or result that you hold encrypted or
  password-protected at rest, and move it only through the analysis pipeline.
  Store samples in a password-protected archive or under a defanged extension so
  an accidental open cannot execute them and an endpoint scan cannot quarantine
  them; disk encryption alone prevents neither. On a hosted service the vendor's
  copy is outside that control and is governed by the disclosure requirement
  below instead.
- Record the analysis platform version with each report so results stay
  reproducible.
- Treat a benign verdict as unproven rather than clean. Samples fingerprint the
  hypervisor, monitor, guest artifacts, and interaction timing to suppress their
  behavior, so record which evasion checks the platform applied alongside the
  verdict. See [MITRE ATT&CK T1497](https://attack.mitre.org/techniques/T1497/).

Apply these to the hosted options as well:

- Confirm task visibility before uploading to a hosted service. The ANY.RUN and
  Joe Sandbox sections above record which tiers expose samples and results.
- Treat any upload to a hosted service as disclosure to the vendor, including on
  a private tier. Check retention, deletion, and data-residency terms against
  the sample's classification before submitting an internal artifact.

Apply these to the self-hosted options as well. On a hosted service the
hypervisor, guest, and network belong to the vendor, so these are contract and
vendor-review questions rather than controls you configure:

- Place detonation hosts on a dedicated network segment with no route to
  production or backup networks.
- Give the guests no route off that segment except the brokered egress path
  below.
- Isolate the guests from each other so a self-propagating sample cannot reach
  a concurrent analysis.
- Block every host interface on that segment from the guests except two: the
  analysis framework's own control and result channel on its approved ports,
  and the brokered-egress listener on its approved ports at the broker's
  segment-side interface. No other service on either host is reachable from a
  guest.
- Reach the management interfaces of the detonation and broker hosts only
  through a separate restricted administrative path, never from the
  detonation segment.
- Expose submission and result interfaces to analysts, and to an orchestrator
  such as Assemblyline, only on a separate inbound path that terminates on the
  detonation host and reaches no guest. Allow connections inbound only on it, so
  the host accepts on that path and never initiates over it, matching the
  direction constraint the Assemblyline placement below states. Without it the
  segment rules above leave the web UI and API of a self-hosted deployment
  unreachable, and the operator recovers access by routing production into
  the detonation segment.
- Treat every Assemblyline deployment node as an analyst-and-orchestrator
  security boundary. Dedicate each node to that role, keep its management and
  maintenance on a restricted administrative path apart from the detonation
  segment, and patch it through the approved update mirror on that path with
  host-initiated access limited to the package-update service. Its only
  connection toward the detonation deployment is the designated inbound
  submission and result path above, which terminates on the detonation host and
  reaches no guest. It must not attach to the detonation segment or accept
  guest-originated or detonation-host-initiated new connections.
- Default-deny guest egress. Provide internet access only through a simulated
  or brokered path that is logged and rate-limited. Run that broker on the
  segment boundary rather than on the detonation host, which carries no other
  workload, so the guests reach it as the one permitted route off the segment
  and not through a detonation-host interface. Allow only guest-initiated flows
  and their stateful replies across the broker, and accept no unsolicited inbound
  connection on its untrusted-side interface. Give that interface an internet
  path that cannot route to or through production or backup networks.
- Keep production credentials, tokens, SSH agents, and mounted shares belonging
  to systems outside the analysis environment off the detonation and broker
  hosts and every Assemblyline deployment node. Give each only role-required
  credentials and public trust anchors for update and recovery verification. The
  detonation host alone receives read-only guest gold-image access; the broker
  has no runtime access to it. Scope Assemblyline credentials to the analyst,
  submission, or result-retrieval function each node provides.
- Never domain-join an analysis guest.
- Disable shared folders, clipboard sharing, and drag-and-drop between guest and
  host.
- Restrict hypervisor console and orchestration API access to the analysis
  team, separately from the analyst path used to read results.
- Pin a reviewed commit or release and version the host software, guest image,
  monitor, and analysis policy as one tested unit.
- Reset every guest to the read-only gold image immediately before each analysis
  as well as after it, and treat the guest disk as tainted until the revert
  completes. A run that ends before its post-analysis revert must not leave a
  tainted guest available to the next submission.
- Dedicate the hypervisor host to analysis and the broker host to brokered
  egress. Run no other workload on either, and patch both as security boundaries
  rather than on a general server schedule. Fetch their updates only from an
  approved mirror on the restricted administrative path, with host-initiated
  access limited to the package-update service and repository-signature
  verification, so maintenance does not require guest egress or a
  production-network route.
- Rebuild any boundary host from known-good media when its off-host logs or
  another incident signal indicates host-level compromise. Rebuild the
  detonation host and the broker host additionally when an escape is
  suspected, because both sit on the guest-reachable path. On that same signal,
  isolate the designated submission-and-result path. Before reconnecting the
  recovered detonation host to it, rebuild every Assemblyline deployment node
  that retrieved or processed result data from that detonation host since its
  last known-good rebuild. A compromised detonation host can return
  attacker-controlled result data over an Assemblyline-initiated connection even
  though it cannot initiate a new connection. A guest snapshot revert does not
  restore a host the sample reached.
- Ship hypervisor and host logs off the detonation host, egress-broker logs off
  the broker host, and Assemblyline deployment-node logs off their nodes as they
  are written. Record on the append-only collector which detonation host
  supplied result data to each Assemblyline deployment node. If that record
  cannot identify every node exposed after a suspected escape, rebuild every
  Assemblyline deployment node before reconnecting the recovered detonation host.
  Configure the collector to alert on boundary-host signals that indicate
  host-level compromise, and require acknowledgement and escalation within 15
  minutes. Use those signals to trigger the rebuild requirement above. A
  compromised boundary host can edit any log it can still write to, so nothing
  held on that host can raise the suspicion the rebuild above depends on. Carry
  that shipping on the restricted administrative path rather than the detonation
  segment, give each shipping host its own append-only credentials to the
  collector, and allow no shipping host access to the collector beyond appending,
  so it cannot rewrite or delete what it already sent.
- On the restricted administrative path, the broker host reaches only the log
  collector and the approved update mirror stated above. Give it no route to
  the hypervisor console, the orchestration API, or the gold-image store,
  because it is the one self-hosted component every sample may reach. Bound
  the detonation host and each Assemblyline deployment node the same way:
  neither reaches another boundary host's management interface on that path,
  and the detonation host's only further reach is the read-only gold-image
  access already granted above.
- Keep guest gold images outside the detonation host's write path, and keep
  known-good rebuild media outside the write path of the detonation host, broker
  host, or Assemblyline deployment node it rebuilds.
- Serve a gold image and its authenticated manifest read-only to the detonation
  host over the restricted administrative path rather than the detonation
  segment. Deliver rebuild media and its manifest for any of those systems only
  through a separate recovery procedure, not a runtime route of the system being
  rebuilt.
- Pair every gold image and rebuild medium with an authenticated manifest from
  a separately administered recovery authority that binds the exact media
  identity, version, and cryptographic digest, rather than a locally recorded
  hash. Keep each medium's expected approved release with the pinned tested unit,
  outside the delivery store's control. For every restore or rebuild, verify the
  manifest's signature against the recovery-verification trust anchor granted
  above, require its signed media identity and version to match that expected
  release, and only then verify the relevant media against its digest. Reject a
  validly signed manifest for any older or otherwise unexpected release.
- Revert by discarding the guest's writable overlay and recreating it from the
  gold image rather than from a snapshot the host can write, because a sample
  that reaches the host can otherwise poison the baseline it is restored from.

## Choose a deployment path

Meet the containment requirements above before detonating a live sample on any
of these paths. For a self-hosted path they are not host-local settings: they
add dedicated hosts, network paths, and administered services well beyond the
detonation host itself. Budget for that infrastructure before choosing a
self-hosted path over a hosted one, which shifts it to the vendor instead.

- Use CAPE with KVM and disposable Windows guests for a self-hosted Cuckoo-style
  analysis service.
- Put Assemblyline in front of CAPE when the workflow needs large-scale intake,
  scoring, enrichment, and analyst queue management. Run it on a separate host,
  because the detonation host is dedicated to analysis, and make it the
  analyst-facing surface of the deployment. Analysts reach results only through
  Assemblyline, and the detonation host's own submission and result interfaces
  on the designated inbound path stay restricted to Assemblyline and the
  operators who administer the deployment. The Assemblyline containment
  requirement above governs the rest of its boundary: it submits to the
  detonation host on that inbound path without attaching to the detonation
  segment. The egress broker remains the guests' only outbound crossing.
- Use DRAKVUF when agentless virtual-machine introspection is more important
  than deployment simplicity.
- Use ANY.RUN or Joe Sandbox when a managed service, live analyst interaction,
  and rapid onboarding outweigh self-hosting, and the vendor's retention and
  data-residency terms are acceptable for the sample's classification.
- Use PANDA when deterministic replay or custom whole-system instrumentation is
  the primary research requirement.
- Use bubblewrap, Firejail, or Sandboxie-Plus only as an additional isolation
  layer for local tools and applications.

## References

- [NIST SP 800-83 Rev. 1: Guide to Malware Incident Prevention and Handling for Desktops and Laptops](https://csrc.nist.gov/pubs/sp/800/83/r1/final)
- [NIST SP 800-125: Guide to Security for Full Virtualization Technologies](https://csrc.nist.gov/pubs/sp/800/125/final)
- [MITRE ATT&CK T1497: Virtualization/Sandbox Evasion](https://attack.mitre.org/techniques/T1497/)

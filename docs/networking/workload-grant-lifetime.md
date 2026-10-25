# Workload grant lifetime

A [workload grant](workload-grants.md) admits connections only while its element lives in the `grants` set of `inet workload_grants`.
Expiry and revoke both end it; [vsock grants](../apps/sbx/vsock-grants.md) end in the `sbx-vsock` proxy instead.

## When a grant ends

- The grant chains cut every packet of a marked connection whose original tuple has left `grants`, in both directions.
  A TCP segment draws a reset to its sender, and anything else is dropped.
- Revoke removes only elements and routes, so its connections keep their marked conntrack entries and stay cut, as at expiry.
- A grant first deletes the marked entries an ended grant left on its paths, so it carries only connections that start under it.
- Once a TCP entry is gone, [`inet workload`](workloads.md) drops the flow's next segment, so an ended TCP connection never passes again.
- A UDP flow has no such guard: after its entry times out, a datagram from the source needs a live grant again.
  A datagram the host sends then is host-to-guest traffic, which grants do not govern.

## Survival across reloads

`networking.nftables.tables` reloads delete and recreate each declared table, which would empty the sets, so the grant table stays outside them.
`workload-grants.service` owns it and loads it with `add` and `flush chain` only, which keeps the elements; a switch, an `nftables` reload or restart, and a restart of the unit all leave live grants in place and ended ones cut.
An `nftables` reload propagates to the unit, which recreates the chains when something deleted the table.
A change to a set's type fails the unit until the table is recreated.
With no rule and no present guest declared, the unit empties the set, deletes the marked conntrack entries, and deletes the table and the grant routes instead.

# Copyright (c) 2026 Bad3r

"""Print a device profile's declared exclude list as JSON.

Arguments: the base list, the host's extra entries (both JSON arrays of
split-tunnel entries) and the host's routed CIDRs (a JSON array of strings).
Each base entry that overlaps a routed CIDR is replaced by the pieces of it
that lie outside every routed CIDR, so routed traffic enters the tunnel while
the rest of the range stays local; the extra entries follow unchanged.
"""

import ipaddress
import json
import sys
from pathlib import Path

base, extra, routed = (json.loads(Path(arg).read_text()) for arg in sys.argv[1:4])
cuts = [ipaddress.ip_network(cidr) for cidr in routed]

out = []
for entry in base:
    original = ipaddress.ip_network(entry["address"])
    pieces = [original]
    for cut in cuts:
        kept = []
        for piece in pieces:
            if cut.version != piece.version or not piece.overlaps(cut):
                kept.append(piece)
            elif cut.subnet_of(piece):
                kept.extend(piece.address_exclude(cut))
            # else the piece lies wholly inside the cut and is dropped
        pieces = kept
    if pieces == [original]:
        out.append(entry)
        continue
    note = "minus the routed ranges"
    description = (
        f"{entry['description']}, {note}" if entry.get("description") else note.capitalize()
    )
    out.extend({"address": str(piece), "description": description} for piece in sorted(pieces))

print(json.dumps(out + extra))

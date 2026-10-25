# ip -batch commands that turn the band into $want; adds precede deletes so no rule lapses.
($want | split("\n") | map(select(. != ""))) as $want
| [ .[]
    | select(.priority >= 31000 and .priority <= 31999 and (.iif // "" | startswith("vn-")))
    | "pref \(.priority) iif \(.iif)"
      + (if .dst then " to \(.dst)" + (if .dstlen then "/\(.dstlen)" else "" end) else "" end)
      + (if .action == "unreachable" then " unreachable" else " lookup \(.table)" end)
  ] as $have
| ($want - $have | map("rule add " + .)) + ($have - $want | map("rule del " + .))
| .[]

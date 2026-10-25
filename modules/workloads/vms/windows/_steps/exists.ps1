# Probe only: whether $Data.path exists.
if (Test-Path -LiteralPath $Data.path) { exit 0 }
exit 10

# Toast helpers shared by the Codex notify program and the Claude Code notify hook.
# The body takes markup; the summary is plain text.
def esc: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
def clip($n): if length > $n then .[:$n - 1] + "…" else . end;
def text: if type == "string" then . else "" end;
# $app plus the payload's working directory name.
def title($app): ((.cwd | text) | rtrimstr("/") | split("/") | last // "") as $dir
  | $app + (if $dir == "" then "" else " · " + $dir end);
# The first three non-blank lines, clipped.
def excerpt: split("\n") | map(select(test("\\S"))) | .[:3] | join("\n") | clip(200);
# Shell assignments for summary and body.
def fields: @sh "summary=\(.summary) body=\(.body | esc)";

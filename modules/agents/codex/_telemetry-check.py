# Copyright (c) 2026 Bad3r

"""Exercise content removal and metadata preservation through the collector."""

import http.client
import json
import os
import socket
import subprocess
import sys
import time
from http import HTTPStatus
from pathlib import Path


def require(*, condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


collector, config = sys.argv[1:]
state = Path(os.environ["TMPDIR"]) / "telemetry-state"
state.mkdir()
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]

events = ["spawn_agent", "wait_agent", "close_agent", "exec_command"]
records = [
    {
        "body": {"stringValue": "codex.tool_result"},
        "attributes": [
            {"key": "event.name", "value": {"stringValue": "codex.tool_result"}},
            {"key": "tool_name", "value": {"stringValue": tool}},
            {"key": "success", "value": {"boolValue": True}},
            {"key": "arguments", "value": {"stringValue": "PRIVATE_PROMPT"}},
            {"key": "output", "value": {"stringValue": "PRIVATE_REPLY"}},
        ],
    }
    for tool in events
]
payload = {"resourceLogs": [{"scopeLogs": [{"logRecords": records}]}]}
with Path("collector.log").open("w+") as log:
    process = subprocess.Popen(
        [
            collector,
            f"--config={config}",
            "--set",
            f"receivers.otlp.protocols.http.endpoint=127.0.0.1:{port}",
        ],
        env={**os.environ, "STATE_DIRECTORY": str(state)},
        stdout=log,
        stderr=log,
    )
    try:
        deadline = time.monotonic() + 20
        while True:
            try:
                connection = http.client.HTTPConnection("127.0.0.1", port, timeout=2)
                try:
                    connection.request(
                        "POST",
                        "/v1/logs",
                        json.dumps(payload),
                        {"Content-Type": "application/json"},
                    )
                    response = connection.getresponse()
                    require(
                        condition=response.status == HTTPStatus.OK, message=str(response.status)
                    )
                    result = json.load(response)
                    require(condition=not result.get("partialSuccess"), message=str(result))
                finally:
                    connection.close()
                break
            except OSError:
                if process.poll() is not None or time.monotonic() >= deadline:
                    raise
                time.sleep(0.1)
    finally:
        process.terminate()
        process.wait(timeout=15)
        log.seek(0)
        print(log.read())

require(condition=process.returncode == 0, message=str(process.returncode))
raw = (state / "logs.jsonl").read_text()
require(condition="PRIVATE_PROMPT" not in raw and "PRIVATE_REPLY" not in raw, message=raw)
exported = [
    record
    for line in raw.splitlines()
    for resource in json.loads(line)["resourceLogs"]
    for scope in resource["scopeLogs"]
    for record in scope["logRecords"]
]
require(condition=len(exported) == len(events), message=str(exported))
for tool, record in zip(events, exported, strict=True):
    attrs = {attr["key"]: attr["value"] for attr in record["attributes"]}
    require(condition="arguments" not in attrs and "output" not in attrs, message=str(attrs))
    require(
        condition=attrs["event.name"] == {"stringValue": "codex.tool_result"}, message=str(attrs)
    )
    require(condition=attrs["tool_name"] == {"stringValue": tool}, message=str(attrs))
    require(condition=attrs["success"] == {"boolValue": True}, message=str(attrs))
print("Tool content removed; all four events and their diagnostic metadata preserved.")

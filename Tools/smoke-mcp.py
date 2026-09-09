#!/usr/bin/env python3
"""Test the shipped stdio executable against temporary synthetic notes, never user data."""
import datetime as dt
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import uuid

server = sys.argv[1] if len(sys.argv) > 1 else "/Applications/Murmur.app/Contents/MacOS/murmur-mcp"

def request(identifier, method, **params):
    return {"jsonrpc": "2.0", "id": identifier, "method": method, "params": params}

def call(identifier, name, **arguments):
    return request(identifier, "tools/call", name=name, arguments=arguments)

with tempfile.TemporaryDirectory(prefix="murmur-mcp-smoke-") as path:
    root = Path(path)
    meeting = root / "smoke-session"
    meeting.mkdir()
    now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()
    manifest = dict(id=meeting.name, title="Synthetic launch review", startedAt=now, endedAt=now,
                    state="noted", attendees=[], speakers=["Maya"], engine="Apple", segmentCount=3, duration=30)
    (meeting / "session.json").write_text(json.dumps(manifest))
    (meeting / "note.md").write_text("## Summary\nThe launchpad review is on Friday.\n")
    (meeting / "notes.json").write_text("[]")
    segments = [dict(id=str(uuid.uuid4()), start=i*10, end=i*10+8, source="call", speaker="Maya", text=f"Source segment {i}.") for i in range(3)]
    (meeting / "transcript.jsonl").write_text("".join(json.dumps(s)+"\n" for s in segments))

    def exchange(messages, writes=False):
        lines = [json.dumps(request(0, "initialize", protocolVersion="2025-11-25", capabilities={}, clientInfo={"name":"smoke", "version":"1"})),
                 json.dumps({"jsonrpc":"2.0", "method":"notifications/initialized"})]
        lines += [json.dumps(message) for message in messages]
        lines.append("{malformed")
        process = subprocess.run([server] + (["--allow-writes"] if writes else []), input="\n".join(lines)+"\n", text=True,
                                 capture_output=True, check=True, timeout=10, env={**os.environ, "MURMUR_SESSIONS_DIR":str(root)})
        output = [json.loads(line) for line in process.stdout.splitlines()]
        assert len(output) == len(messages) + 2, "Unexpected output, or a reply to a notification"
        assert output[0]["result"]["protocolVersion"] == "2025-11-25"
        assert output[-1]["error"]["code"] == -32700
        return {item["id"]:item for item in output[:-1]}

    results = exchange([
        request(1, "tools/list"), call(2, "list_sessions"), call(3, "get_session", id=meeting.name),
        call(4, "get_transcript", id=meeting.name, limit=2), call(5, "get_transcript", id=meeting.name, limit=2, offset=2),
        call(6, "search", query="launchpad"), request(7, "resources/read", uri="murmur://sessions/"+meeting.name),
        call(8, "save_summary", id=meeting.name, text="Blocked", expected_version=1),
    ])
    assert "save_summary" not in [t["name"] for t in results[1]["result"]["tools"]]
    assert results[2]["result"]["structuredContent"]["count"] == 1
    assert results[3]["result"]["structuredContent"]["note_version"] == 1
    assert results[4]["result"]["structuredContent"]["next_offset"] == 2
    assert results[5]["result"]["structuredContent"]["next_offset"] is None
    assert results[5]["result"]["structuredContent"]["segments"][0]["text"] == "Source segment 2."
    assert results[6]["result"]["structuredContent"]["count"] == 1
    assert "launchpad" in results[7]["result"]["contents"][0]["text"]
    assert results[8]["error"]["code"] == -32602
    results = exchange([
        call(1, "save_summary", id=meeting.name, text="## Updated summary\nReviewed on Friday.", expected_version=1),
        call(2, "save_summary", id=meeting.name, text="Stale overwrite", expected_version=1),
    ], writes=True)
    assert results[1]["result"]["structuredContent"]["note_version"] == 2
    assert results[2]["result"]["isError"] is True
    assert "launchpad" in (meeting / "note.1.md").read_text()
    assert "Stale overwrite" not in (meeting / "note.md").read_text()
print("MCP executable passed: stdio lifecycle, pagination, search, resources, read-only access and revision-protected writes.")

#!/usr/bin/env python3
"""Functional check of the agents' language servers (stdlib only).

Starts each server with the command and args an agent uses, sends
initialize, didOpen, and documentSymbol, and passes with >=1 symbol.
It answers workspace/configuration with null per item and sends no
workspace/didChangeConfiguration, as Copilot CLI 1.0.116 does.
Servers: Copilot CLI (`copilot lsp list --json` plus plugin manifests)
and Claude Code (`claude plugin list --json`, each enabled plugin's
lspServers); a server both agents run the same way is started once.

Usage: lsp-check.py [--agent all|copilot|claude] [--config FILE]
                    [--only id1,id2] [--timeout SEC] [--settle SEC]
"""
import argparse
import collections
import json
import os
import queue
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

# Fixtures by extension: (language id, content).
FIXTURES = {
    ".sh": ("shellscript", 'greet() {\n  echo "hi $1"\n}\nNAME=x\n'
            'greet "$NAME"\n'),
    ".yaml": ("yaml", "name: demo\nitems:\n  - a\nnested:\n  key: value\n"),
    ".json": ("json", '{\n  "name": "demo",\n  "list": [1, 2]\n}\n'),
    ".html": ("html", "<!DOCTYPE html>\n<html>\n<head><title>t</title>"
              "</head>\n<body><div id=\"main\"><p>hi</p></div></body>\n"
              "</html>\n"),
    ".css": ("css", "body { color: red; }\n.main { margin: 0; }\n"),
    ".dockerfile": ("dockerfile", "FROM debian:trixie\nRUN echo hi\n"
                    "CMD [\"bash\"]\n"),
    ".md": ("markdown", "# Title\n\n## Section\n\nText.\n"),
    ".toml": ("toml", '[package]\nname = "demo"\n\n[tool]\nkey = 1\n'),
    ".py": ("python", "def add(a: int, b: int) -> int:\n    return a + b\n"
            "\n\nclass Foo:\n    pass\n"),
    ".ts": ("typescript", "export function add(a: number, b: number) {\n"
            "  return a + b;\n}\nexport class Foo {}\n"),
}


class Client:
    """Minimal JSON-RPC client over stdio with Content-Length framing."""

    def __init__(self, proc):
        self.proc, self.seq, self.diags = proc, 0, 0
        self.msgs = queue.Queue()
        self.log = collections.deque(maxlen=25)
        threading.Thread(target=self._read, daemon=True).start()
        threading.Thread(target=self._stderr, daemon=True).start()

    def _read(self):
        out = self.proc.stdout
        while True:
            length = None
            while True:
                line = out.readline()
                if not line:
                    return self.msgs.put(None)
                if not line.strip():
                    break
                key, _, val = line.decode().partition(":")
                if key.lower() == "content-length":
                    length = int(val)
            if length is not None:
                self.msgs.put(json.loads(out.read(length)))

    def _stderr(self):
        for line in self.proc.stderr:
            self.log.append("stderr: " + line.decode(errors="replace")
                            .rstrip())

    def send(self, msg):
        # Omit null params: tsc rejects shutdown with "params": null.
        if msg.get("params", 0) is None:
            msg = {k: v for k, v in msg.items() if k != "params"}
        body = json.dumps(dict(msg, jsonrpc="2.0")).encode()
        self.proc.stdin.write(b"Content-Length: %d\r\n\r\n" % len(body) + body)
        self.proc.stdin.flush()

    def notify(self, method, params):
        self.send({"method": method, "params": params})

    def next(self, deadline):
        """Handle server messages until a response arrives (returned) or
        the deadline passes (None). Raises EOFError if the server exits."""
        while (left := deadline - time.monotonic()) > 0:
            try:
                msg = self.msgs.get(timeout=left)
            except queue.Empty:
                return None
            if msg is None:
                raise EOFError("server exited, code %s" % self.proc.poll())
            method = msg.get("method")
            if method is None:
                return msg
            params = msg.get("params") or {}
            if method == "textDocument/publishDiagnostics":
                self.diags = max(self.diags, len(params.get("diagnostics")
                                                 or []))
            elif method in ("window/logMessage", "window/showMessage"):
                self.log.append("log: " + str(params.get("message"))[:300])
            if "id" in msg:
                result = None
                if method == "workspace/configuration":
                    result = [None for _ in params.get("items", [])]
                self.send({"id": msg["id"], "result": result})
        return None

    def request(self, method, params, deadline):
        self.seq += 1
        rid = self.seq
        self.send({"id": rid, "method": method, "params": params})
        while (msg := self.next(deadline)) is not None:
            if msg.get("id") == rid:
                if "error" in msg:
                    raise LookupError(msg["error"].get("message"))
                return msg.get("result")
        raise TimeoutError("no answer to " + method)


def count_symbols(items):
    return sum(1 + count_symbols(s.get("children") or [])
               for s in items or [])


def check(spec, ws, timeout, settle):
    """Run one server; return (ok, symbols, diagnostics, note, log)."""
    ext = next((e for e in spec["fileExtensions"] if e in FIXTURES), None)
    if ext is None:
        return False, 0, 0, "no fixture for " + str(spec["fileExtensions"]), []
    if shutil.which(spec["command"]) is None:
        return False, 0, 0, "command not found: " + spec["command"], []
    lang, text = FIXTURES[ext]
    doc = (ws / ("fixture" + ext)).as_uri()
    proc = subprocess.Popen(
        [spec["command"]] + spec.get("args", []), cwd=ws,
        env=dict(os.environ, **spec.get("env", {})), stdin=subprocess.PIPE,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    client = Client(proc)
    deadline = time.monotonic() + timeout
    syms, note = 0, ""
    try:
        client.request("initialize", {
            "processId": os.getpid(), "rootUri": ws.as_uri(),
            "rootPath": str(ws),
            "workspaceFolders": [{"uri": ws.as_uri(), "name": "ws"}],
            "initializationOptions": spec.get("initializationOptions"),
            "capabilities": {
                "workspace": {"configuration": True,
                              "workspaceFolders": True},
                "textDocument": {
                    "documentSymbol": {
                        "hierarchicalDocumentSymbolSupport": True},
                    "publishDiagnostics": {}}}}, deadline)
        client.notify("initialized", {})
        client.notify("textDocument/didOpen", {"textDocument": {
            "uri": doc, "languageId": lang, "version": 1, "text": text}})
        # Ask again while empty: some servers index after didOpen.
        settle_end = min(deadline, time.monotonic() + settle)
        while True:
            if syms == 0:
                syms = count_symbols(client.request(
                    "textDocument/documentSymbol",
                    {"textDocument": {"uri": doc}}, deadline))
            if syms or time.monotonic() >= settle_end:
                break
            client.next(min(settle_end, time.monotonic() + 1))
        client.request("shutdown", None, min(deadline, time.monotonic() + 5))
        client.notify("exit", None)
    except (TimeoutError, EOFError, LookupError, OSError) as err:
        note = "%s: %s" % (type(err).__name__, err)
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
    return syms > 0, syms, client.diags, note, list(client.log)


def run_json(cmd):
    return json.loads(subprocess.run(cmd, check=True, capture_output=True,
                                     text=True).stdout)


def manifest_servers(root, rels):
    """lspServers of the first manifest found under root ({} if none);
    a string value is a path to a JSON file with the servers."""
    for rel in rels:
        if (root / rel).is_file():
            lsp = json.loads((root / rel).read_text()).get("lspServers")
            if isinstance(lsp, str):
                lsp = json.loads((root / lsp).read_text())
                lsp = lsp.get("lspServers", lsp)
            if lsp:
                return lsp
    if (root / ".lsp.json").is_file():
        return json.loads((root / ".lsp.json").read_text())
    return {}


def copilot_servers(config):
    """[(id, spec)] from `copilot lsp list --json` (or a file in that
    shape); that output has no command, so it comes from the plugin
    manifest or lsp-config.json, unless the entry carries it."""
    entries = (json.loads(Path(config).read_text()) if config
               else run_json(["copilot", "lsp", "list", "--json"]))
    home = Path(os.environ.get("COPILOT_HOME", Path.home() / ".copilot"))
    roots, servers = None, []
    for entry in entries:
        spec = entry if "command" in entry else None
        if spec is None and entry.get("sourcePlugin"):
            if roots is None:
                roots = {p["name"]: Path(p["rootPath"]) for p in run_json(
                    ["copilot", "plugin", "list", "--json"])
                    if p.get("enabled")}
            spec = manifest_servers(
                roots.get(entry["sourcePlugin"], Path("/nonexistent")),
                (".github/plugin/plugin.json", "plugin.json",
                 ".claude-plugin/plugin.json")).get(entry["id"])
        elif spec is None and (home / "lsp-config.json").is_file():
            spec = json.loads((home / "lsp-config.json").read_text()).get(
                "lspServers", {}).get(entry["id"])
        spec = dict(spec or {"command": "<unresolved>"},
                    fileExtensions=entry["fileExtensions"])
        servers.append((entry["id"], spec))
    return servers


def claude_servers():
    """[(id, spec)] from each enabled Claude Code plugin's lspServers;
    Claude keeps a copy of the manifest in the plugin's installPath."""
    servers = []
    for plugin in run_json(["claude", "plugin", "list", "--json"]):
        if not plugin.get("enabled") or not plugin.get("installPath"):
            continue
        lsp = manifest_servers(Path(plugin["installPath"]),
                               (".claude-plugin/plugin.json",))
        for sid, spec in lsp.items():
            exts = list(spec.get("extensionToLanguage", {}))
            servers.append((sid, dict(spec, fileExtensions=exts)))
    return servers


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--agent", choices=("all", "copilot", "claude"),
                        default="all", help="whose servers (default all)")
    parser.add_argument("--config", help="server list instead of Copilot "
                        "CLI's, `copilot lsp list --json` shape")
    parser.add_argument("--only", help="comma-separated server ids")
    parser.add_argument("--timeout", type=float, default=60,
                        help="per-server timeout in seconds (default 60)")
    parser.add_argument("--settle", type=float, default=8,
                        help="seconds to retry empty symbols (default 8)")
    args = parser.parse_args()
    only = set(args.only.split(",")) if args.only else None
    servers = []
    if args.agent in ("all", "copilot"):
        servers += [("copilot", *s) for s in copilot_servers(args.config)]
    if args.agent in ("all", "claude"):
        servers += [("claude", *s) for s in claude_servers()]
    servers = [s for s in servers if not only or s[1] in only]
    if not servers:
        print("FAIL no language servers found")
        return 1
    failed, seen = False, {}
    with tempfile.TemporaryDirectory(prefix="lsp-check-") as tmp:
        ws = Path(tmp).resolve()
        for ext, (_, text) in FIXTURES.items():
            (ws / ("fixture" + ext)).write_text(text)
        for agent, sid, spec in servers:
            name = "%s/%s" % (agent, sid)
            cmd = " ".join([spec["command"]] + spec.get("args", []))
            key = json.dumps([spec["command"], spec.get("args", []),
                              spec.get("env", {}), spec["fileExtensions"],
                              spec.get("initializationOptions")])
            if key in seen:
                ok, first = seen[key]
                print("%s %s same as %s (%s)" % (
                    "PASS" if ok else "FAIL", name, first, cmd), flush=True)
                failed |= not ok
                continue
            ok, syms, diags, note, log = check(
                spec, ws, args.timeout, args.settle)
            seen[key] = (ok, name)
            print("%s %s symbols=%d diagnostics=%d (%s) %s" % (
                "PASS" if ok else "FAIL", name, syms, diags, cmd, note),
                flush=True)
            if not ok:
                failed = True
                for line in log[-15:]:
                    print("    " + line)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

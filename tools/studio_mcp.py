"""
studio_mcp.py: a small stdio client for Roblox Studio's BUILT-IN MCP server (StudioMCP.exe).

Studio ships the server next to RobloxStudioBeta.exe. It needs Studio to be running with
"Enable Studio as MCP server" on (Assistant > ... > Manage MCP Servers). Any script can then
drive Studio: start / stop Play, run Luau in the Edit / Server / Client data model, click GUI,
press keys, take screenshots. tools/studio_smoke.py is built on it.

    from studio_mcp import StudioMCP
    with StudioMCP() as mcp:
        sid = mcp.wait_for_studio("DroneFarm.rbxlx")
        print(mcp.luau(sid, "Server", "return #workspace:GetChildren()"))

Standard library only. Windows (Studio's own platform).
"""

from __future__ import annotations

import base64
import glob
import json
import os
import queue
import subprocess
import sys
import threading
import time

VERSIONS = os.path.join(os.environ.get("LOCALAPPDATA", ""), "Roblox", "Versions")


def newest(name: str) -> str:
    """The newest Studio version folder's copy of `name` (StudioMCP.exe, RobloxStudioBeta.exe)."""
    found = glob.glob(os.path.join(VERSIONS, "*", name))
    if not found:
        raise FileNotFoundError(f"{name} not found under {VERSIONS} (is Roblox Studio installed?)")
    return max(found, key=os.path.getmtime)


class ToolError(RuntimeError):
    pass


class StudioMCP:
    def __init__(self, verbose: bool = False):
        self.verbose = verbose
        self.proc = subprocess.Popen(
            [newest("StudioMCP.exe"), "--stdio"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        self.inbox: queue.Queue = queue.Queue()
        self.next_id = 1
        threading.Thread(target=self._read, daemon=True).start()
        threading.Thread(target=self._drain_stderr, daemon=True).start()
        self._request(
            "initialize",
            {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "dronefarm-tools", "version": "1"}},
        )
        self._send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})

    # ------------------------------------------------------------------ transport
    def _read(self):
        for line in self.proc.stdout:
            line = line.strip()
            if line:
                try:
                    self.inbox.put(json.loads(line))
                except json.JSONDecodeError:
                    pass

    def _drain_stderr(self):
        for line in self.proc.stderr:
            if self.verbose:
                sys.stderr.write("[StudioMCP] " + line.decode(errors="replace"))

    def _send(self, message: dict):
        self.proc.stdin.write((json.dumps(message) + "\n").encode())
        self.proc.stdin.flush()

    def _request(self, method: str, params: dict, timeout: float = 180):
        rid = self.next_id
        self.next_id += 1
        self._send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                message = self.inbox.get(timeout=1)
            except queue.Empty:
                continue
            if message.get("id") == rid:
                if "error" in message:
                    raise ToolError(json.dumps(message["error"]))
                return message["result"]
        raise TimeoutError(f"{method}: no answer in {timeout} s")

    # ------------------------------------------------------------------ tools
    def call(self, tool: str, timeout: float = 180, **arguments) -> tuple[str, list[bytes]]:
        """Calls a tool. Returns (text, images). Raises ToolError when the tool reports an error."""
        result = self._request("tools/call", {"name": tool, "arguments": arguments}, timeout)
        texts, images = [], []
        for item in result.get("content", []):
            if item.get("type") == "text":
                texts.append(item["text"])
            elif item.get("type") == "image":
                images.append(base64.b64decode(item["data"]))
        text = "\n".join(texts)
        if result.get("isError"):
            raise ToolError(f"{tool}: {text}")
        return text, images

    def studios(self) -> list[dict]:
        text, _ = self.call("list_roblox_studios")
        try:
            return json.loads(text).get("studios", [])
        except json.JSONDecodeError:
            return []

    def wait_for_studio(self, file_hint: str | None = None, timeout: float = 90) -> str:
        """The id of a connected Studio (the one with `file_hint` open, if given)."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            for studio in self.studios():
                if file_hint is None or studio.get("file") == file_hint:
                    return studio["id"]
            time.sleep(1)
        raise TimeoutError(
            "no Studio connected: open the place and turn on Assistant > ... > Manage MCP Servers > "
            "'Enable Studio as MCP server'"
        )

    def mode(self, sid: str) -> str:
        text, _ = self.call("get_studio_state", studio_id=sid)
        for line in text.splitlines():
            if "Current Studio Mode:" in line:
                return line.split(":", 1)[1].strip()
        return "Unknown"

    def luau(self, sid: str, datamodel: str, code: str, timeout: float = 120) -> str:
        text, _ = self.call("execute_luau", timeout=timeout, studio_id=sid, datamodel_type=datamodel, code=code)
        return text

    def luau_json(self, sid: str, datamodel: str, code: str, timeout: float = 120):
        """Runs `code`, which must `return HttpService:JSONEncode(...)`; returns the decoded value."""
        text = self.luau(sid, datamodel, code, timeout)
        start = min((i for i in (text.find("{"), text.find("[")) if i >= 0), default=-1)
        if start < 0:
            raise ToolError(f"expected JSON from Luau, got: {text[:300]}")
        return json.loads(text[start:])

    def click(self, sid: str, path: str):
        self.call(
            "user_mouse_input",
            studio_id=sid,
            datamodel_type="Client",
            actions=[{"action": "moveTo", "instance_path": path}, {"action": "mouseButtonClick", "mouse_button": "left"}],
        )

    def keys(self, sid: str, actions: list[dict]):
        self.call("user_keyboard_input", studio_id=sid, datamodel_type="Client", actions=actions)

    def screenshot(self, sid: str, path: str, capture_id: str = "Smoke") -> str | None:
        _, images = self.call("screen_capture", studio_id=sid, capture_id=capture_id)
        if not images:
            return None
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(images[0])
        return path

    def console(self, sid: str) -> str:
        text, _ = self.call("get_console_output", studio_id=sid)
        return text

    def close(self):
        try:
            self.proc.stdin.close()
            self.proc.terminate()
        except Exception:
            pass

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()

"""Integration checks against a disposable fake Niri IPC socket."""
import json
import os
import socket
import subprocess
import tempfile
import threading
import unittest
from pathlib import Path

CORE = Path(__file__).resolve().parents[1] / "presentation-hub/bin/presentation-hub-core"


class FakeNiri:
    def __init__(self, path, *, outputs=None, windows=None, move=True):
        self.path = path
        self.outputs = outputs if outputs is not None else {
            "eDP-1": {"name": "eDP-1", "logical": {}},
            "HDMI-A-1": {"name": "HDMI-A-1", "logical": {}},
        }
        self.windows = windows if windows is not None else [{"id": 42, "workspace_id": 1, "app_id": "firefox", "title": "Example"}]
        self.move = move
        self.requests = []
        self.sock = socket.socket(socket.AF_UNIX)
        self.sock.bind(path)
        self.sock.listen()
        self.sock.settimeout(0.1)
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self.serve, daemon=True)

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *args):
        self.stop.set()
        self.thread.join(timeout=2)
        self.sock.close()

    def serve(self):
        while not self.stop.is_set():
            try:
                conn, _ = self.sock.accept()
            except socket.timeout:
                continue
            with conn:
                raw = b""
                while not raw.endswith(b"\n"):
                    chunk = conn.recv(65536)
                    if not chunk:
                        break
                    raw += chunk
                try:
                    req = json.loads(raw)
                    self.requests.append(req)
                    if req == "Outputs": result = {"Outputs": self.outputs}
                    elif req == "Workspaces": result = {"Workspaces": [{"id": 1, "output": "eDP-1"}, {"id": 2, "output": "HDMI-A-1"}]}
                    elif req == "Windows": result = {"Windows": self.windows}
                    elif isinstance(req, dict) and "Action" in req:
                        action = req["Action"]["MoveWindowToMonitor"]
                        if self.move:
                            for window in self.windows:
                                if window["id"] == action["id"]:
                                    window["workspace_id"] = 2
                        result = "Handled"
                    else:
                        conn.sendall(b'{"Err":"unknown request"}\n')
                        continue
                    conn.sendall(json.dumps({"Ok": result}).encode() + b"\n")
                except (ValueError, KeyError, OSError):
                    continue


class IpcTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.socket = str(Path(self.tmp.name) / "niri.sock")
        self.addCleanup(self.tmp.cleanup)

    def run_core(self, *args):
        return subprocess.run([str(CORE), *args], env={**os.environ, "NIRI_SOCKET": self.socket}, text=True, capture_output=True, timeout=5)

    def test_move_confirms_result_and_uses_requested_id(self):
        with FakeNiri(self.socket) as fake:
            result = self.run_core("move", "--window", "42", "--output", "HDMI-A-1")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout), {"window_id": 42, "output": "HDMI-A-1"})
            self.assertIn({"Action": {"MoveWindowToMonitor": {"id": 42, "output": "HDMI-A-1"}}}, fake.requests)

    def test_disconnected_display_does_not_send_move(self):
        with FakeNiri(self.socket, outputs={"eDP-1": {"name": "eDP-1", "logical": {}}}) as fake:
            result = self.run_core("move", "--window", "42", "--output", "HDMI-A-1")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("destination display", result.stderr)
            self.assertFalse(any(isinstance(r, dict) and "Action" in r for r in fake.requests))

    def test_closed_window_does_not_send_move(self):
        with FakeNiri(self.socket, windows=[]) as fake:
            result = self.run_core("move", "--window", "42", "--output", "HDMI-A-1")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("window no longer exists", result.stderr)
            self.assertFalse(any(isinstance(r, dict) and "Action" in r for r in fake.requests))

    def test_noop_action_does_not_report_success(self):
        with FakeNiri(self.socket, move=False):
            result = self.run_core("move", "--window", "42", "--output", "HDMI-A-1")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Could not confirm", result.stderr)

if __name__ == "__main__":
    unittest.main()

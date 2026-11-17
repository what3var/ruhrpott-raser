#!/usr/bin/env python3
# Ein kleiner Ersatz des Spielservers für die Tests des Launchers (nur der Vertrag: /api/register, /api/login, /api/version, /api/news,
# /api/status, /files/<pfad>). Das Release ist ein Ordner; die Dateiliste wird bei jeder Anfrage neu daraus berechnet.
#
#   python3 -I mock_server.py --port 7480 --release <ordner> [--control <datei.json>]
#
# Die Steuerdatei (bei jeder Anfrage neu gelesen) macht den Server absichtlich falsch:
#   {"corrupt": ["bin/game"],                       diese Dateien kommen mit falschen Bytes (gleiche Größe)
#    "extra": [{"path": "../boese", "size": 1, "sha256": "..."}],   zusätzliche Einträge der Dateiliste
#    "version": "0.1.4", "notes": "..."}
import argparse
import hashlib
import json
import os
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

USERS = {"anna": "geheim1"}


def release_files(root):
    files = []
    for base, dirs, names in os.walk(root):
        dirs.sort()
        for name in sorted(names):
            full = os.path.join(base, name)
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            with open(full, "rb") as f:
                data = f.read()
            files.append({"path": rel, "size": len(data), "sha256": hashlib.sha256(data).hexdigest()})
    return files


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def control(self):
        path = self.server.control_file
        if path and os.path.exists(path):
            with open(path, encoding="utf-8") as f:
                return json.load(f)
        return {}

    def send(self, status, body, kind="application/json"):
        if not isinstance(body, bytes):
            body = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

    def account(self, register):
        length = int(self.headers.get("Content-Length", "0"))
        try:
            data = json.loads(self.rfile.read(length).decode("utf-8"))
            user, password = data["user"], data["password"]
        except Exception:
            return self.send(400, {"error": "Ungültige Anfrage"})
        if not isinstance(user, str) or not isinstance(password, str) or len(user) < 2 or len(password) < 4:
            return self.send(400, {"error": "Name (ab 2 Zeichen) und Passwort (ab 4 Zeichen) nötig"})
        if register:
            if user in USERS:
                return self.send(409, {"error": "Den Namen \"" + user + "\" gibt es schon"})
            USERS[user] = password
        elif USERS.get(user) != password:
            return self.send(401, {"error": "Name oder Passwort falsch"})
        self.send(200, {"token": "tok-" + hashlib.sha256(user.encode()).hexdigest()[:24], "user": user, "admin": user == "admin",
                        "expires": "2026-11-18T12:00:00Z"})

    def do_POST(self):
        if self.path == "/api/register":
            return self.account(True)
        if self.path == "/api/login":
            return self.account(False)
        self.send(404, {"error": "nicht gefunden"})

    def do_GET(self):
        ctl = self.control()
        root = self.server.release
        if self.path == "/api/status":
            return self.send(200, {"players": 3, "region": "Bochum-Innenstadt", "uptime": 123})
        if self.path == "/api/news":
            return self.send(200, [{"date": "2026-11-17", "title": "Launcher da", "text": "Der Launcher lädt jetzt das Spiel."},
                                   {"date": "2026-11-10", "title": "Bochum", "text": "Die Innenstadt ist befahrbar. Äöü ß."}])
        if self.path == "/api/version":
            files = release_files(root) + ctl.get("extra", [])
            return self.send(200, {"version": ctl.get("version", "0.1.3"), "notes": ctl.get("notes", "Erste Testversion.\nMit Launcher."),
                                   "files": files})
        if self.path.startswith("/files/"):
            rel = urllib.parse.unquote(self.path[len("/files/"):])
            parts = rel.split("/")
            if any(p in ("", ".", "..") for p in parts) or "\\" in rel:
                return self.send(404, {"error": "nicht gefunden"})
            full = os.path.join(root, *parts)
            if not os.path.isfile(full):
                return self.send(404, {"error": "nicht gefunden"})
            with open(full, "rb") as f:
                data = f.read()
            if rel in ctl.get("corrupt", []):
                data = bytes((b ^ 0x5A) for b in data)
            return self.send(200, data, "application/octet-stream")
        self.send(404, {"error": "nicht gefunden"})

    def log_message(self, fmt, *args):
        sys.stderr.write("mock: " + (fmt % args) + "\n")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--port", type=int, default=7480)
    p.add_argument("--release", required=True)
    p.add_argument("--control", default="")
    a = p.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", a.port), Handler)
    server.release = os.path.abspath(a.release)
    server.control_file = a.control
    print("mock server on port", a.port, flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()

#!/usr/bin/env python3

import json
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

HOST = "127.0.0.1"
PORT = int(os.environ.get("NATIVE_TEST_BROKER_PORT", "17899"))

lock = threading.Lock()
sessions = {}
counter = 0


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, *_args):
        pass

    def send_json(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_empty(self, status):
        self.send_response(status)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def send_raw(self, status, body):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)

        if parsed.path == "/health":
            self.send_json(200, {"ok": True})
            return

        if parsed.path == "/identity":
            username = query.get("username", [""])[0]

            if username == "forbidden":
                self.send_empty(403)
                return

            self.send_json(
                200,
                {
                    "username": username,
                    "display_name": (
                        "Alice Directory"
                        if username == "alice"
                        else username
                    ),
                    "account_source": (
                        "nss"
                        if username == "alice"
                        else "local"
                    ),
                },
            )
            return

        if parsed.path == "/status":
            session_id = query.get("session_id", [""])[0]

            with lock:
                state = sessions.get(session_id)

                if state is None:
                    self.send_empty(404)
                    return

                if state["cancelled"]:
                    self.send_empty(404)
                    return

                state["polls"] += 1
                polls = state["polls"]
                username = state["username"]

            base = {
                "status": "pending",
                "username": username,
                "user_code": "ABCD-EFGH",
                "verification_uri_complete":
                    "https://example.invalid/device?user_code=ABCD-EFGH",
                "qr_path": "/tmp/native-test-qr.png",
                "expires_at": int(time.time()) + 120,
            }

            if username == "qrless":
                base.pop("qr_path", None)
                self.send_json(200, base)
                return

            if username == "denied" and polls >= 2:
                base["status"] = "denied"
                self.send_json(200, base)
                return

            if username == "unavailable" and polls >= 2:
                base["status"] = "error"
                base["error"] = "temporarily_unavailable"
                self.send_json(200, base)
                return

            if username == "missing-status" and polls >= 2:
                base.pop("status", None)
                self.send_json(200, base)
                return

            if username == "malformed" and polls == 2:
                self.send_raw(200, b"{")
                return

            if username == "expire" and polls >= 2:
                base["status"] = "error"
                base["error"] = "expired"
                self.send_json(200, base)
                return

            if username == "mismatch" and polls >= 2:
                base["status"] = "approved"
                base["username"] = "different-user"
                self.send_json(200, base)
                return

            if polls == 2:
                base["rate_limited"] = True
                base["retry_after_seconds"] = 17
                self.send_json(200, base)
                return

            if polls >= 4:
                base["status"] = "approved"
                self.send_json(200, base)
                return

            self.send_json(200, base)
            return

        self.send_empty(404)

    def do_POST(self):
        global counter

        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)

        if parsed.path == "/start":
            username = query.get("username", [""])[0]

            if username == "forbidden":
                self.send_empty(403)
                return

            if username == "throttle":
                self.send_empty(429)
                return

            if username == "hang":
                # Accepts the connection and holds it open far longer
                # than any test's requestTimeoutMs, to prove the client
                # times out and recovers instead of waiting forever.
                # Still responds eventually, so the late/stale-response
                # rejection path (generation check) is exercised too.
                time.sleep(5)

            if not username:
                self.send_empty(403)
                return

            with lock:
                counter += 1
                session_id = f"test-{counter}-{username}"

                sessions[session_id] = {
                    "username": username,
                    "polls": 0,
                    "cancelled": False,
                }

            self.send_json(
                200,
                {"session_id": session_id},
            )
            return

        if parsed.path == "/cancel":
            session_id = query.get("session_id", [""])[0]

            with lock:
                state = sessions.get(session_id)

                if state is None:
                    self.send_empty(404)
                    return

                state["cancelled"] = True

            self.send_empty(200)
            return

        self.send_empty(404)


server = ThreadingHTTPServer((HOST, PORT), Handler)

print(
    f"NATIVE_TEST_BROKER=READY {HOST}:{PORT}",
    flush=True,
)

server.serve_forever()

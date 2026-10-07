#!/usr/bin/env python3
"""Fake 3x-ui subscription upstream for smoke tests.

Behaviors are selected by the first path segment, mimicking how the proxy
builds upstream URLs: SERVERS entries look like http://up:8080/s/<behavior>/
and the proxy appends the sub id, so the path is /s/<behavior>/<sub_id>.

  ok1    200 + Subscription-Userinfo + Profile-Title + Profile-Update-Interval
  ok2    200 + different Userinfo + Announce (base64-prefixed, like 3x-ui)
  missb  400 "Error!"          — 3x-ui v3.0.x unknown sub id
  missn  404                   — 3x-ui v3.4+ unknown sub id
  err    500 "boom"
  hang   sleeps 30s before replying — hangs past the proxy's 2s timeout
"""
import base64
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def b64(s):
    return base64.b64encode(s.encode()).decode()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        parts = self.path.strip("/").split("/")
        behavior = parts[1] if len(parts) > 1 else "ok1"
        sub = parts[-1]

        if behavior == "missb":
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b"Error!")
            return
        if behavior == "missn":
            self.send_response(404)
            self.end_headers()
            return
        if behavior == "err":
            self.send_response(500)
            self.end_headers()
            self.wfile.write(b"boom")
            return
        if behavior == "hang":
            time.sleep(30)

        body = "vless://%s-%s\n" % (behavior, sub)
        payload = b64(body)
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        if behavior == "ok1":
            self.send_header("Subscription-Userinfo", "upload=100; download=200; total=2147483648; expire=1900000000")
            self.send_header("Profile-Title", b64("Тест"))
            self.send_header("Profile-Update-Interval", "24")
        if behavior == "ok2":
            self.send_header("Subscription-Userinfo", "upload=50; download=150; total=1073741824; expire=0")
            self.send_header("Announce", "base64:" + b64("Объявление"))
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload.encode())

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    import os
    import ssl

    server = ThreadingHTTPServer(("0.0.0.0", 8080), Handler)
    cert, key = os.environ.get("TLS_CERT"), os.environ.get("TLS_KEY")
    if cert and key:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(cert, key)
        server.socket = ctx.wrap_socket(server.socket, server_side=True)
    server.serve_forever()

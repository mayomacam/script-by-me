#!/usr/bin/env python3

import sys
from http.server import BaseHTTPRequestHandler, HTTPServer


class RequestHandler(BaseHTTPRequestHandler):

    def handle_any_request(self):
        client_ip, client_port = self.client_address

        # Read request body if present
        content_length = self.headers.get("Content-Length")

        if content_length:
            try:
                body = self.rfile.read(int(content_length))
            except (ValueError, ConnectionError):
                body = b""
        else:
            body = b""

        # Print request
        print("\n" + "=" * 80)
        print(f"FROM    : {client_ip}:{client_port}")
        print(f"METHOD  : {self.command}")
        print(f"PATH    : {self.path}")
        print("-" * 80)

        print("HEADERS:")
        for name, value in self.headers.items():
            print(f"{name}: {value}")

        print("-" * 80)
        print("BODY:")

        if body:
            print(body.decode("utf-8", errors="replace"))
        else:
            print("(empty)")

        print("=" * 80)
        sys.stdout.flush()

        # Response
        response = (
            f"Thanks for {self.command} request\n"
            f"Request received from: {client_ip}:{client_port}\n"
        ).encode()

        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(response)))
        self.end_headers()

        if self.command != "HEAD":
            self.wfile.write(response)
            self.wfile.flush()

    # HTTP methods
    def do_GET(self):
        self.handle_any_request()

    def do_POST(self):
        self.handle_any_request()

    def do_PUT(self):
        self.handle_any_request()

    def do_PATCH(self):
        self.handle_any_request()

    def do_DELETE(self):
        self.handle_any_request()

    def do_OPTIONS(self):
        self.handle_any_request()

    def do_HEAD(self):
        self.handle_any_request()

    def do_CONNECT(self):
        self.handle_any_request()

    def do_TRACE(self):
        self.handle_any_request()


def main():

    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <port>")
        sys.exit(1)

    try:
        port = int(sys.argv[1])

        if not 1 <= port <= 65535:
            raise ValueError

    except ValueError:
        print("Invalid port")
        sys.exit(1)

    server = HTTPServer(("0.0.0.0", port), RequestHandler)

    print(f"[*] Listening on 0.0.0.0:{port}")
    print("[*] Press Ctrl+C to stop")
    sys.stdout.flush()

    try:
        server.serve_forever()

    except KeyboardInterrupt:
        print("\n[*] Stopping server")

    finally:
        server.server_close()


if __name__ == "__main__":
    main()
    

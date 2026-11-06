#!/usr/bin/env python3
"""Give the owned hosted test command an independently reachable loopback network tripwire."""
import argparse
import http.server
import json
import os
from pathlib import Path
import subprocess
import threading


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('configuration', choices=['Debug', 'Release'])
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if os.environ.get('CI') != 'true' or not command:
        parser.error('Hosted CI and an explicit owned test command are required')
    paths = []
    lock = threading.Lock()

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            with lock:
                if self.path != '/status':
                    paths.append(self.path)
                snapshot = list(paths)
            data = json.dumps(snapshot).encode() if self.path == '/status' else b'control-live'
            self.send_response(200)
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Content-Type', 'application/json' if self.path == '/status' else 'text/plain')
            self.end_headers()
            self.wfile.write(data)

        def do_POST(self):
            self.do_GET()

        def do_HEAD(self):
            self.do_GET()

        def log_message(self, *_args):
            pass

    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    server.daemon_threads = True
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    environment = dict(os.environ, MOSTLYTEXT_PREVIEW_TRIPWIRE='http://127.0.0.1:%s' % server.server_port)
    # Xcode's test runner only forwards explicit TEST_RUNNER_* values to its application child.
    environment['TEST_RUNNER_MOSTLYTEXT_PREVIEW_TRIPWIRE'] = environment['MOSTLYTEXT_PREVIEW_TRIPWIRE']
    if args.configuration == 'Release':
        environment['MOSTLYTEXT_PREVIEW_RELEASE_PROBE'] = '1'
        environment['TEST_RUNNER_MOSTLYTEXT_PREVIEW_RELEASE_PROBE'] = '1'
    try:
        result = subprocess.run(command, env=environment, timeout=660)
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
        with lock:
            snapshot = list(paths)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps({'paths': snapshot, 'denied_requests': [p for p in snapshot if p.startswith('/denied/')]}, indent=2) + '\n')
    if result.returncode != 0:
        raise SystemExit(result.returncode)
    if '/control' not in snapshot or '/control-webkit' not in snapshot or any(p.startswith('/denied/') for p in snapshot):
        raise SystemExit('The HTTP positive control or observed network denial failed')


if __name__ == '__main__':
    main()

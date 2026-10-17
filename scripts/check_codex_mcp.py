#!/usr/bin/env python3
# Check that installed Codex can initialize Capture and discover all 13 MCP tools.
# Run manually after building: python3 scripts/check_codex_mcp.py <path-to-capture-mcp>.
# Requires Codex on PATH. Uses temporary configuration; makes no model calls or changes to user configuration.
# Optional development check only; not packaged with Capture.

import json
import os
from pathlib import Path
import queue
import subprocess
import sys
import tempfile
import threading
import time

helper = str(Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory(prefix='capture-codex-check-') as tmp:
    root = Path(tmp)
    (root / 'config.toml').write_text(
        '[mcp_servers.capture]\ncommand = ' + json.dumps(helper) + '\n'
        '[mcp_servers.capture.env]\nCAPTURE_MCP_TEST_SOCKET_DIRECTORY = ' + json.dumps(tmp + '/unused') + '\n')
    with open(root / 'stderr.log', 'w') as log:
        process = subprocess.Popen(['codex', 'app-server', '--stdio'], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=log, env=dict(os.environ, CODEX_HOME=tmp))
        messages = queue.Queue()
        def read():
            for line in process.stdout:
                messages.put(json.loads(line))
        threading.Thread(target=read, daemon=True).start()
        def request(identifier, method, params):
            process.stdin.write((json.dumps({'id': identifier, 'method': method, 'params': params}) + '\n').encode())
            process.stdin.flush()
            deadline = time.monotonic() + 25
            while time.monotonic() < deadline:
                value = messages.get(timeout=max(.01, deadline - time.monotonic()))
                if value.get('id') == identifier:
                    assert 'error' not in value, value
                    return value['result']
            raise AssertionError('Codex discovery timeout')
        try:
            request(1, 'initialize', {'clientInfo': {'name': 'capture-integration-check', 'version': '1'}, 'capabilities': {'experimentalApi': True}})
            process.stdin.write(b'{"method":"initialized"}\n'); process.stdin.flush()
            thread = request(2, 'thread/start', {'ephemeral': True, 'cwd': tmp})
            result = request(3, 'mcpServerStatus/list', {'serverName': 'capture', 'threadId': thread['thread']['id']})
            capture = next(server for server in result['data'] if server['name'] == 'capture')
            print(json.dumps({'toolCount': len(capture['tools']), 'toolsError': capture.get('toolsError'), 'runtimeStatus': capture.get('runtimeStatus'), 'serverInfo': capture.get('serverInfo')}))
            assert capture.get('runtimeStatus') == 'connected' and not capture.get('toolsError') and len(capture['tools']) == 13, 'Codex did not discover Capture tools'
            print('PASS: installed Codex initializes Capture and discovers all 13 tools')
        finally:
            process.terminate()
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired: process.kill(); process.wait()

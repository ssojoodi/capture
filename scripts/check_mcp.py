#!/usr/bin/env python3
"""Client-neutral JSON-RPC integration checks against the bundled MCP helper and live app fixture."""
import base64
import json
import os
from pathlib import Path
import select
import struct
import subprocess
import sys
import tempfile
import time

helper_path, fixture_path = map(os.path.abspath, sys.argv[1:])

def wait_for(predicate, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(.03)
    raise AssertionError('Timed out waiting for fixture')

with tempfile.TemporaryDirectory(prefix='capture-mcp-check-') as tmp:
    folder = Path(tmp)
    log = open(folder / 'process.log', 'w')
    fixture = subprocess.Popen([fixture_path, tmp], stdout=log, stderr=log)
    clients = []
    try:
        wait_for(lambda: (folder / 'ready').exists() or fixture.poll() is not None)
        assert fixture.poll() is None, (folder / 'process.log').read_text()
        directory = (folder / 'ready').read_text()
        assert oct(os.stat(directory).st_mode & 0o777) == '0o700'
        assert oct(os.stat(directory + '/agent.sock').st_mode & 0o777) == '0o600'

        class Client:
            def __init__(self, capabilities=None):
                self.process = subprocess.Popen([helper_path], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                    stderr=log, env=dict(os.environ, CAPTURE_MCP_TEST_SOCKET_DIRECTORY=directory))
                clients.append(self.process)
                self.serial = 0
                result = self.rpc('initialize', {'protocolVersion': '2025-06-18', 'capabilities': capabilities or {}, 'clientInfo': {'name': 'Capture tests', 'version': '1'}})
                assert result['serverInfo']['name'] == 'Capture'
                self.send({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
            def send(self, value):
                self.process.stdin.write(json.dumps(value).encode() + b'\n')
                self.process.stdin.flush()
            def rpc(self, method, params):
                self.serial += 1
                self.send({'jsonrpc': '2.0', 'id': self.serial, 'method': method, 'params': params})
                assert select.select([self.process.stdout], [], [], 20)[0], 'MCP response timeout'
                line = self.process.stdout.readline()
                assert line, (folder / 'process.log').read_text()
                value = json.loads(line)
                assert value.get('id') == self.serial and 'error' not in value, value
                return value['result']
            def tool(self, name, args=None, error=None):
                result = self.rpc('tools/call', {'name': name, 'arguments': args or {}})
                payload = json.loads(result['content'][0]['text'])
                if error:
                    assert result.get('isError') and payload['error']['code'] == error, result
                else:
                    assert not result.get('isError'), result
                return payload, result

        def control(action, doc=None):
            (folder / 'ack').unlink(missing_ok=True)
            (folder / 'control.tmp').write_text(json.dumps({'action': action, 'documentID': doc or ''}))
            os.replace(folder / 'control.tmp', folder / 'control.json')
            wait_for(lambda: (folder / 'ack').exists())

        client = Client({'experimental': {'codex/sandbox-state-meta': {}, 'test/nested': {'enabled': True, 'values': [1, None]}},
                         'roots': {'listChanged': True}})
        assert client.rpc('ping', {}) == {}
        names = {t['name'] for t in client.rpc('tools/list', {})['tools']}
        assert len(names) == 13 and {'blur_region', 'preview_document', 'copy_image'} <= names
        first, _ = client.tool('open_image', {'path': str(folder / 'input.png')})
        second, _ = client.tool('open_image', {'path': str(folder / 'input.png')})
        doc = first['documentID']
        rev = first['revision']
        args = lambda: {'documentID': doc, 'revision': rev}
        first, _ = client.tool('add_annotation', dict(args(), kind='rectangle', properties={'bounds': {'x': -50, 'y': -25, 'width': 140, 'height': 70}, 'color': '#FF0000', 'strokeWidth': 4}))
        rev = first['revision']; annotation = first['annotationID']
        assert first['canvasBounds']['x'] < -50
        inspected, _ = client.tool('inspect_document', {'documentID': second['documentID']})
        assert not inspected['annotations'], 'Commands must not follow frontmost window'
        preview, result = client.tool('preview_document', {'documentID': doc})
        assert preview['revision'] == rev and preview['preview']['originX'] < 0
        png = base64.b64decode(result['content'][1]['data'])
        assert png[:8] == b'\x89PNG\r\n\x1a\n'
        assert struct.unpack('>II', png[16:24]) == (preview['preview']['width'], preview['preview']['height'])
        old = rev
        changed, _ = client.tool('update_annotation', dict(args(), annotationID=annotation, properties={'color': '#00FF00'}))
        rev = changed['revision']
        client.tool('delete_annotation', {'documentID': doc, 'revision': old, 'annotationID': annotation}, error='stale_revision')
        undo, _ = client.tool('undo', args()); rev = undo['revision']; assert rev not in (old, changed['revision'])
        redo, _ = client.tool('redo', args()); rev = redo['revision']
        for kind, props in [('arrow', {'start': {'x': 30, 'y': 40}, 'end': {'x': 220, 'y': 140}}),
                            ('ellipse', {'bounds': {'x': 100, 'y': 200, 'width': 120, 'height': 80}}),
                            ('text', {'bounds': {'x': 260, 'y': 40, 'width': 300, 'height': 80}, 'text': 'Agent annotation', 'fontSize': 32})]:
            value, _ = client.tool('add_annotation', dict(args(), kind=kind, properties=props)); rev = value['revision']
        value, _ = client.tool('blur_region', dict(args(), bounds={'x': 60, 'y': 200, 'width': 120, 'height': 100})); rev = value['revision']
        for ext in ['png', 'jpg']:
            output = folder / ('export.' + ext)
            client.tool('export_image', dict(args(), path=str(output)))
            assert output.stat().st_size > 100
            client.tool('export_image', dict(args(), path=str(output)), error='file_exists')
            client.tool('export_image', dict(args(), path=str(output), overwrite=True))
        value, _ = client.tool('crop_document', dict(args(), bounds={'x': 10, 'y': 10, 'width': 400, 'height': 300})); rev = value['revision']
        assert not value['annotations'] and value['imageSize']['width'] == 400
        value, _ = client.tool('undo', args()); rev = value['revision']; assert len(value['annotations']) == 4
        control('user_edit', doc)
        client.tool('delete_annotation', dict(args(), annotationID=annotation), error='stale_revision')
        control('busy', doc)
        client.tool('inspect_document', {'documentID': doc}, error='document_busy')
        control('resume', doc)
        wait_for(lambda: True)
        # A second connection must see the same documents and fresh state.
        other = Client()
        listed, _ = other.tool('list_documents'); assert doc in [d['documentID'] for d in listed['documents']]
        control('toggle')
        client.tool('list_documents', error='connection_unavailable')
        client.tool('list_documents', error='connection_unavailable')
        control('toggle')
        listed, _ = client.tool('list_documents'); assert doc in [d['documentID'] for d in listed['documents']]
        (folder / 'control.json').write_text(json.dumps({'action': 'quit'}))
        fixture.wait(timeout=10)
        client.tool('list_documents', error='connection_unavailable')
        assert not Path(directory + '/agent.sock').exists()
        print('PASS: real MCP initialize/list/call, preview PNG, all edits, two documents/clients, stale/busy errors, exports, disable/re-enable, quit and socket cleanup')
    except Exception:
        log.flush()
        print((folder / 'process.log').read_text(), file=sys.stderr)
        raise
    finally:
        for process in clients + [fixture]:
            if process.poll() is None:
                process.terminate()
                try: process.wait(timeout=5)
                except subprocess.TimeoutExpired: process.kill()
        log.close()

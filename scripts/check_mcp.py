#!/usr/bin/env python3
# Test MCP discovery, editing, previews, exports, validation, and connection lifecycle.
# Called by check_mcp.sh with paths to the built helper and isolated test app.
# Uses temporary files and separate app preferences. Development check only; not packaged with Capture.

import base64
import json
import os
import plistlib
import shutil
import signal
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
    lazy_folder = folder / "lazy-launch"
    try:
        wait_for(lambda: (folder / 'ready').exists() or fixture.poll() is not None)
        assert fixture.poll() is None, (folder / 'process.log').read_text()
        directory = (folder / 'ready').read_text()
        assert oct(os.stat(directory).st_mode & 0o777) == '0o700'
        assert oct(os.stat(directory + '/agent.sock').st_mode & 0o777) == '0o600'

        class Client:
            def __init__(self, capabilities=None, executable=helper_path, socket_directory=directory, bufsize=-1):
                environment = dict(os.environ)
                environment.pop('CAPTURE_MCP_TEST_SOCKET_DIRECTORY', None)
                if socket_directory is not None:
                    environment['CAPTURE_MCP_TEST_SOCKET_DIRECTORY'] = socket_directory
                self.process = subprocess.Popen([executable], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                    stderr=log, env=environment, bufsize=bufsize)
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

        def control(action, doc=None, target=folder):
            (target / 'ack').unlink(missing_ok=True)
            (target / 'control.tmp').write_text(json.dumps({'action': action, 'documentID': doc or ''}))
            os.replace(target / 'control.tmp', target / 'control.json')
            wait_for(lambda: (target / 'ack').exists())

        client = Client({'experimental': {'codex/sandbox-state-meta': {}, 'test/nested': {'enabled': True, 'values': [1, None]}},
                         'roots': {'listChanged': True}})
        assert client.rpc('ping', {}) == {}
        names = {t['name'] for t in client.rpc('tools/list', {})['tools']}
        assert len(names) == 13 and {'blur_region', 'preview_document', 'copy_image'} <= names
        client.tool('open_image', {'path': 42}, error='invalid_arguments')
        client.tool('list_documents', {'unexpected': True}, error='invalid_arguments')
        client.tool('unknown_tool', {}, error='unknown_tool')
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

        # Exercise the production launch path with a private app, without the socket override.
        lazy_folder.mkdir()
        bundle = lazy_folder / 'Capture Launch Fixture.app'
        contents = bundle / 'Contents'
        (contents / 'MacOS').mkdir(parents=True)
        (contents / 'Helpers').mkdir()
        shutil.copy2(fixture_path, contents / 'MacOS' / 'CaptureFixture')
        bundled_helper = contents / 'Helpers' / 'capture-mcp'
        shutil.copy2(helper_path, bundled_helper)
        with (contents / 'Info.plist').open('wb') as output:
            plistlib.dump({'CFBundleExecutable': 'CaptureFixture', 'CFBundleIdentifier': 'com.capture.launchfixture.' + folder.name,
                          'CFBundleName': 'Capture Launch Fixture', 'CFBundlePackageType': 'APPL',
                          'CaptureFixtureFolder': str(lazy_folder)}, output)
        lazy = Client(executable=str(bundled_helper), socket_directory=None, bufsize=0)
        assert lazy.rpc('ping', {}) == {}
        assert len(lazy.rpc('tools/list', {})['tools']) == 13
        assert not (lazy_folder / 'launches').exists(), 'Initialize/ping/list must not launch the app'
        lazy.tool('unknown_tool', error='unknown_tool')
        lazy.tool('open_image', {'path': 42}, error='invalid_arguments')
        assert not (lazy_folder / 'launches').exists(), 'Invalid initial calls must not launch the app'
        # Queue two calls before reading either reply to exercise actor reentrancy during launch.
        for identifier in [100, 101]:
            lazy.send({'jsonrpc': '2.0', 'id': identifier, 'method': 'tools/call',
                       'params': {'name': 'list_documents', 'arguments': {}}})
        for _ in range(2):
            assert select.select([lazy.process.stdout], [], [], 20)[0], 'Lazy launch timeout'
            reply = json.loads(lazy.process.stdout.readline())
            assert reply['id'] in [100, 101] and not reply['result'].get('isError'), reply
            assert json.loads(reply['result']['content'][0]['text'])['documents']
        assert (lazy_folder / 'launches').read_text() == '1', 'Concurrent calls must launch once'
        lazy.tool('list_documents')
        assert (lazy_folder / 'launches').read_text() == '1', 'Existing app must be reused'
        control('toggle', target=lazy_folder)
        existing = Client(executable=str(bundled_helper), socket_directory=None, bufsize=0)
        existing.tool('list_documents', error='connection_unavailable')
        assert (lazy_folder / 'launches').read_text() == '1', 'Disabled control must not launch a second app'
        control('toggle', target=lazy_folder)
        existing.tool('list_documents')
        assert (lazy_folder / 'launches').read_text() == '1', 'A new helper must reuse the running app'
        (lazy_folder / 'control.json').write_text(json.dumps({'action': 'quit'}))
        socket = Path((lazy_folder / 'ready').read_text()) / 'agent.sock'
        wait_for(lambda: not socket.exists())
        lazy.tool('list_documents', error='connection_unavailable')
        lazy.tool('list_documents', error='connection_unavailable')
        assert lazy.rpc('ping', {}) == {} and len(lazy.rpc('tools/list', {})['tools']) == 13
        assert (lazy_folder / 'launches').read_text() == '1', 'Quit must not trigger another launch'
        print('PASS: discovery and invalid calls leave app closed; concurrent first calls launch once; existing app reuse and explicit quit respected')

    except Exception:
        log.flush()
        print((folder / 'process.log').read_text(), file=sys.stderr)
        raise
    finally:
        if (lazy_folder / 'pid').exists():
            try: os.kill(int((lazy_folder / 'pid').read_text()), signal.SIGTERM)
            except ProcessLookupError: pass
        for process in clients + [fixture]:
            if process.poll() is None:
                process.terminate()
                try: process.wait(timeout=5)
                except subprocess.TimeoutExpired: process.kill()
        log.close()

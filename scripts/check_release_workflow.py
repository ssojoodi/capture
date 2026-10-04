#!/usr/bin/env python3
"""Check release orchestration without signing credentials or Apple submissions."""
import io
import json
import os
from pathlib import Path
import plistlib
import runpy
import subprocess
import tempfile
from types import SimpleNamespace
from unittest.mock import patch

release = runpy.run_path(str(Path(__file__).with_name('release.py')))
main = release['main']
identity = 'Developer ID Application: Test Developer (ABCDEFGHIJ)'

with tempfile.TemporaryDirectory() as temporary:
    repo = Path(temporary).resolve()
    (repo / 'Config').mkdir()
    (repo / 'Config/Version.xcconfig').write_text('MARKETING_VERSION = 2026.10.3\nCURRENT_PROJECT_VERSION = 2\n')
    calls = []
    submissions = []
    failure = None

    def run(*args, capture=False):
        args = tuple(map(str, args))
        calls.append(args)
        if args[0] == 'security':
            return f'"{identity}"'
        if args[:2] == ('xcrun', 'xcodebuild'):
            assert args[args.index('-derivedDataPath') + 1] == str(repo / '.build/release/DerivedData')
            assert 'ONLY_ACTIVE_ARCH=NO' in args
            assert not any(arg.startswith(('MARKETING_VERSION=', 'CURRENT_PROJECT_VERSION=')) for arg in args)
        elif args[0] == 'ditto' and args[2].endswith('.app'):
            app = Path(args[2])
            (app / 'Contents').mkdir(parents=True)
            (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
                'CFBundleShortVersionString': '2026.10.3', 'CFBundleVersion': '2'}))
        elif len(args) > 1 and args[1] == 'scripts/create_dmg.sh':
            Path(args[3]).write_bytes(b'validated candidate')
        if failure and args[:len(failure)] == failure:
            raise subprocess.CalledProcessError(1, args)

    def notarize(path, profile, staging, label):
        submissions.append((path, label))
        assert Path(path).suffix == '.dmg' and label == 'dmg'
        if failure == ('notarize',):
            raise RuntimeError('Notarization rejected')

    def metadata(args, **kwargs):
        assert args[:2] == ['codesign', '-d']
        return SimpleNamespace(stderr='TeamIdentifier=ABCDEFGHIJ', stdout=b'')

    original_directory = Path.cwd()
    try:
        with patch.dict(main.__globals__, {'__file__': str(repo / 'scripts/release.py'), 'run': run, 'notarize': notarize}), \
             patch.dict(os.environ, {'VERSION': '9.9.9'}), \
             patch('sys.argv', ['release.py', '--identity', identity, '--profile', 'test-notary']), \
             patch('sys.stdin', io.StringIO()), \
             patch('builtins.input', side_effect=AssertionError('Release must not prompt')), \
             patch('subprocess.run', side_effect=metadata):
            main()
            assert len(submissions) == 1
            for symbols in ('Capture.app.dSYM', 'CaptureCore.framework.dSYM'):
                assert any(call[0] == 'ditto' and call[2].endswith('/symbols/' + symbols) for call in calls)
            target = repo / 'web-page/Capture.dmg'
            original = target.read_bytes()
            manifest = (target.parent / 'release.json').read_bytes()
            assert json.loads(manifest)['version'] == '2026.10.3'
            assert json.loads(manifest)['build'] == '2'
            assert any(call[0] == 'bash' and call[1] == 'scripts/create_dmg.sh' and call[3].endswith('Capture-2026.10.3-2.dmg') for call in calls)
            assert not any(call[0] == 'open' for call in calls)
            # Failed notarization or final validation must not replace the download.
            for failure in [('codesign', '--force'), ('notarize',), ('xcrun', 'stapler', 'validate'), ('spctl',), ('hdiutil', 'verify')]:
                try:
                    main()
                except (RuntimeError, subprocess.CalledProcessError):
                    pass
                else:
                    raise AssertionError(f'Failure was ignored: {failure}')
                assert target.read_bytes() == original
                assert (target.parent / 'release.json').read_bytes() == manifest
    finally:
        os.chdir(original_directory)

print('PASS: configured bundle version, reusable cache, explicit signing, accepted notarization, and failed-release preservation.')

# Apple must explicitly accept the submission; a successful process exit alone is insufficient.
with tempfile.TemporaryDirectory() as temporary:
    staging = Path(temporary)
    for status, returncode in [('Accepted', 0), ('Invalid', 0), ('In Progress', 0), ('Accepted', 1)]:
        commands = []
        def submission(args, **kwargs):
            commands.append(args)
            if args[2] == 'submit':
                kwargs['stdout'].write(json.dumps({'id': 'test-submission', 'status': status}))
            return SimpleNamespace(returncode=returncode)
        with patch('subprocess.run', side_effect=submission):
            try:
                release['notarize'](staging / 'candidate.dmg', 'test-profile', staging, 'dmg')
            except RuntimeError:
                assert status != 'Accepted' or returncode != 0
                assert any(command[2] == 'log' for command in commands)
            else:
                assert status == 'Accepted' and returncode == 0
print('PASS: rejected, pending, and failed notarization cannot be published.')

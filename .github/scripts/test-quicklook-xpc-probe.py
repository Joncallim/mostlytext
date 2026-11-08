#!/usr/bin/env python3
"""Pure XPC process/own-request controls; no service or product is launched."""
import importlib.util
import datetime as dt
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('xpc_probe', HERE / 'prepare-quicklook-jsc-probe.py')
PREP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREP)
FIXTURE = HERE.parent / 'quicklook-jsc-probe'
SIGN_SPEC = importlib.util.spec_from_file_location('xpc_sign', FIXTURE / 'resign-embedded-xpc.py')
SIGN = importlib.util.module_from_spec(SIGN_SPEC)
SIGN_SPEC.loader.exec_module(SIGN)
CAPTURE_SPEC = importlib.util.spec_from_file_location('xpc_launch_capture', HERE / 'capture-quicklook-xpc-launch.py')
CAPTURE = importlib.util.module_from_spec(CAPTURE_SPEC)
CAPTURE_SPEC.loader.exec_module(CAPTURE)


def example():
    record = {'kind': 'mostlytext-qlxpc-capability', 'request_id': 3,
              'provider_pid': 111, 'service_pid': 222, 'started_uptime': 12.5}
    messages = ['QL_XPC_PROBE begin id=3 provider=111 start=12.5',
                'QL_XPC_SERVICE replied id=3 pid=222 sandbox=1',
                'QL_XPC_PROBE admitted id=3 provider=111 service=222']
    return record, messages


def hold_example():
    record = {
        'kind': 'mostlytext-qlxpc-hold-lifecycle', 'request_id': 4,
        'provider_pid': 111, 'service_pid': 222, 'started_uptime': 20.0,
        'ready_uptime': 21.0, 'invalidated_uptime': 21.5,
        'samples': [
            {'uptime': 21.1, 'check_uptime': 21.2, 'service': 'expected', 'provider': 'expected', 'window': True},
            {'uptime': 21.6, 'check_uptime': 21.7, 'service': 'expected', 'provider': 'expected', 'window': True},
            {'uptime': 22.0, 'check_uptime': 22.1, 'service': 'absent', 'provider': 'expected', 'window': True},
            {'uptime': 24.5, 'check_uptime': 24.6, 'service': 'absent', 'provider': 'expected', 'window': True},
        ],
        'marker_visible': True, 'provider_remained': True, 'window_remained': True,
        'service_identity_valid': True, 'service_departed_by_deadline': True,
    }
    messages = [
        'QL_XPC_HOLD begin id=4 provider=111 start=20.0',
        'QL_XPC_HOLD service-ready id=4 pid=222 sandbox=1',
        'QL_XPC_HOLD admitted id=4 provider=111 service=222 ready=21.0',
        'QL_XPC_HOLD invalidated id=4 provider=111 service=222 at=21.5',
    ]
    return record, messages


class XPCObservationTests(unittest.TestCase):
    def test_fixed_hold_lifecycle_requires_own_request_and_real_retirement(self):
        row, messages = hold_example()
        PREP.validate_xpc_hold_observation(row, messages)
        window_warming = dict(row, samples=[dict(row['samples'][0], window=False)] + row['samples'][1:])
        PREP.validate_xpc_hold_observation(window_warming, messages)
        for changed in (
            dict(row, service_pid=333),
            dict(row, invalidated_uptime=22.9),
            dict(row, service_departed_by_deadline=False),
            dict(row, samples=[dict(sample, service='expected') for sample in row['samples']]),
            dict(row, samples=row['samples'][:2] + [dict(row['samples'][2], provider='absent')]
                 + row['samples'][3:]),
            dict(row, samples=row['samples'][:2] + [dict(row['samples'][2], window=False)]
                 + row['samples'][3:]),
            dict(row, samples=row['samples'][:3] + [dict(row['samples'][3], service='expected')]),
            dict(row, samples=row['samples'][:3]),
        ):
            with self.assertRaises(RuntimeError):
                PREP.validate_xpc_hold_observation(changed, messages)
        for bad_messages in (messages[:3], messages + messages[-1:],
                             messages[:1] + ['QL_XPC_HOLD service-ready id=4 pid=333 sandbox=1'] + messages[2:]):
            with self.assertRaises(RuntimeError):
                PREP.validate_xpc_hold_observation(row, bad_messages)

    def test_hold_fixture_keeps_fixed_request_no_new_authority_and_independent_observer(self):
        provider = (FIXTURE / 'Provider/XPCCapability.swift').read_text()
        service = (FIXTURE / 'XPCService/main.swift').read_text()
        ui = (FIXTURE / 'FinderTests/ZXPCFinderHoldTests.swift').read_text()
        self.assertIn('guard requestID > 0', provider)
        self.assertIn('guard id > 0, first', service)
        self.assertIn('Thread.sleep(forTimeInterval: 10)', service)
        self.assertIn('asyncAfter(deadline: .now() + .milliseconds(500))', provider)
        self.assertIn('"/bin/ps"', ui)
        self.assertIn('kill(pid, 0)', ui)
        self.assertIn('serviceDepartedByDeadline', ui)
        self.assertNotIn('SIGKILL', ui + provider + service)
        self.assertEqual(plistlib.loads((FIXTURE / 'XPCService.entitlements').read_bytes()),
                         {'com.apple.security.app-sandbox': True})

    def test_system_diagnostic_selects_only_actual_xpc_provider_request(self):
        begin = {'subsystem': CAPTURE.PROVIDER_SUBSYSTEM,
                 'processImagePath': '/fixture/QLReplyProbeProvider', 'processID': 111,
                 'eventMessage': 'QL_XPC_PROBE begin id=3 provider=111 start=12.5',
                 'timestamp': '2026-11-08 19:41:38.646394+0000'}
        other = dict(begin, eventMessage='QL_JSC_PROBE result={}', timestamp='2026-11-08 19:41:33+0000')
        observed, start, end = CAPTURE.request_window([other, begin])
        self.assertEqual(observed, dt.datetime.fromisoformat(begin['timestamp']))
        self.assertEqual((end - start).total_seconds(), 7)
        self.assertIn('--predicate', CAPTURE.log_command(start, end))
        self.assertEqual(CAPTURE.log_command(start, end)[-1], CAPTURE.PREDICATE)
        for rows in ([], [begin, begin], [dict(begin, processID=222)]):
            with self.assertRaises(RuntimeError):
                CAPTURE.request_window(rows)

    def test_hold_diagnostic_selects_only_fixed_fourth_request(self):
        ping = {'subsystem': CAPTURE.PROVIDER_SUBSYSTEM,
                'processImagePath': '/fixture/QLReplyProbeProvider', 'processID': 111,
                'eventMessage': 'QL_XPC_PROBE begin id=3 provider=111 start=12.5',
                'timestamp': '2026-11-08 19:41:38.646394+0000'}
        hold = dict(ping, eventMessage='QL_XPC_HOLD begin id=4 provider=111 start=13.5',
                    timestamp='2026-11-08 19:41:39.646394+0000')
        observed, start, end = CAPTURE.request_window([ping, hold], hold=True)
        self.assertEqual(observed, dt.datetime.fromisoformat(hold['timestamp']))
        self.assertLessEqual((end - start).total_seconds(), 8)
        for rows in ([ping], [hold, hold], [dict(hold, processID=222)]):
            with self.assertRaises(RuntimeError):
                CAPTURE.request_window(rows, hold=True)
        system = {'processImagePath': '/sbin/launchd', 'processID': 1,
                  'timestamp': '2026-11-08 19:41:39.646500+0000',
                  'eventMessage': 'service lifecycle'}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'provider-events.json').write_text(json.dumps([ping, hold]))
            raw = json.dumps([system]).encode()
            run = mock.Mock(return_value=subprocess.CompletedProcess([], 0, raw, b''))
            manifest = CAPTURE.capture(root, run=run, hold=True)
            self.assertEqual(manifest['status'], 'captured')
            self.assertEqual((root / 'xpc-hold-system-events.json').read_bytes(), raw)
            self.assertFalse((root / 'xpc-system-events.json').exists())
            self.assertEqual(run.call_args.kwargs, {'capture_output': True, 'timeout': 30})

    def test_system_diagnostic_retains_bounded_exact_query_and_rejects_wrong_scope(self):
        begin = {'subsystem': CAPTURE.PROVIDER_SUBSYSTEM,
                 'processImagePath': '/fixture/QLReplyProbeProvider', 'processID': 111,
                 'eventMessage': 'QL_XPC_PROBE begin id=3 provider=111 start=12.5',
                 'timestamp': '2026-11-08 19:41:38.646394+0000'}
        system = {'processImagePath': '/sbin/launchd', 'processID': 1,
                  'timestamp': '2026-11-08 19:41:38.646500+0000',
                  'eventMessage': 'service lookup'}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'provider-events.json').write_text(json.dumps([begin]))
            raw = json.dumps([system]).encode()
            run = mock.Mock(return_value=subprocess.CompletedProcess([], 0, raw, b''))
            manifest = CAPTURE.capture(root, run=run)
            self.assertEqual(manifest['status'], 'captured')
            self.assertEqual(manifest['events'], 1)
            self.assertEqual((root / 'xpc-system-events.json').read_bytes(), raw)
            self.assertEqual(run.call_args.kwargs, {'capture_output': True, 'timeout': 30})
            self.assertEqual(run.call_args.args[0][-1], CAPTURE.PREDICATE)
            for changed in (dict(system, processImagePath='/usr/bin/Finder'),
                            dict(system, timestamp='2026-11-08 19:41:50+0000')):
                with self.assertRaises(RuntimeError):
                    CAPTURE.validate_system_events(json.dumps([changed]).encode(),
                                                   dt.datetime.fromisoformat(manifest['start']),
                                                   dt.datetime.fromisoformat(manifest['end']))
            with self.assertRaises(RuntimeError):
                CAPTURE.validate_system_events(b' ' * (CAPTURE.MAX_LOG_BYTES + 1),
                                               dt.datetime.fromisoformat(manifest['start']),
                                               dt.datetime.fromisoformat(manifest['end']))

    def test_one_exact_observation_passes(self):
        row, messages = example()
        PREP.validate_xpc_observation(row, messages)

    def test_missing_or_duplicate_process_evidence_refuses(self):
        row, messages = example()
        for bad in (messages[:1], messages[1:], messages[:2], messages[::2],
                    messages + messages[:1], messages + messages[1:2], messages + messages[2:]):
            with self.assertRaises(RuntimeError):
                PREP.validate_xpc_observation(row, bad)

    def test_wrong_request_or_process_refuses(self):
        row, messages = example()
        for bad in ('QL_XPC_PROBE admitted id=4 provider=111 service=222',
                    'QL_XPC_PROBE admitted id=3 provider=111 service=111',
                    'QL_XPC_PROBE admitted id=3 provider=999 service=222'):
            with self.assertRaises(RuntimeError):
                PREP.validate_xpc_observation(row, messages[:2] + [bad])
        with self.assertRaises(RuntimeError):
            PREP.validate_xpc_observation(row, [messages[0],
                                                'QL_XPC_SERVICE replied id=3 pid=333 sandbox=1', messages[2]])

    def test_invalid_types_and_extra_fields_refuse(self):
        row, messages = example()
        for key, value in (('service_pid', True), ('request_id', 0), ('started_uptime', float('nan')),
                           ('provider_pid', '111')):
            with self.assertRaises(RuntimeError):
                PREP.validate_xpc_observation(dict(row, **{key: value}), messages)
        with self.assertRaises(RuntimeError):
            PREP.validate_xpc_observation(dict(row, fabricated=True), messages)

    def test_provider_authority_remains_minimal(self):
        PREP.validate_provider_entitlements({'com.apple.security.app-sandbox': True,
                                             'com.apple.security.files.user-selected.read-only': True})
        with self.assertRaises(AssertionError):
            PREP.validate_provider_entitlements({'com.apple.security.app-sandbox': True,
                                                 'com.apple.security.files.user-selected.read-only': True,
                                                 'com.apple.security.temporary-exception.mach-lookup.global-name': True})

    def test_service_source_and_signed_entitlements_are_exact(self):
        expected = {'com.apple.security.app-sandbox': True}
        self.assertEqual(plistlib.loads((FIXTURE / 'XPCService.entitlements').read_bytes()), expected)
        xml = plistlib.dumps(expected)
        signed = subprocess.CompletedProcess([], 0, b'', b'Executable=/fixture\n' + xml)
        SIGN.require_exact_entitlements(SIGN.entitlements_from_codesign(signed))
        for extra in ({'com.apple.security.temporary-exception.files.absolute-path.read-only': ['/']},
                      {'com.apple.security.temporary-exception.mach-lookup.global-name':
                       ['com.apple.testmanagerd', 'com.apple.dt.testmanagerd.runner',
                        'com.apple.coresymbolicationd']}):
            with self.assertRaises(RuntimeError):
                SIGN.require_exact_entitlements(expected | extra)

    def test_re_sign_is_bound_to_extension_copy_not_app_copy(self):
        root = Path('/Users/runner/work/_temp/mostlytext-qljsc')
        environment = {'GITHUB_ACTIONS': 'true', 'GITHUB_REPOSITORY': 'Joncallim/mostlytext',
                       'GITHUB_EVENT_NAME': 'workflow_dispatch', 'RUNNER_ENVIRONMENT': 'github-hosted',
                       'RUNNER_OS': 'macOS', 'RUNNER_TEMP': str(root.parent),
                       'SRCROOT': str(root / 'fixture'),
                       'TARGET_BUILD_DIR': str(root / 'build/Build/Products/Release'),
                       'TARGET_NAME': 'QLReplyProbeProvider', 'WRAPPER_NAME': 'QLReplyProbeProvider.appex',
                       'CONFIGURATION': 'Release'}
        with mock.patch.dict(SIGN.os.environ, environment, clear=True), \
                mock.patch.object(SIGN.os, 'getuid', return_value=501), \
                mock.patch.object(SIGN.os, 'geteuid', return_value=501), \
                mock.patch.object(SIGN.pwd, 'getpwuid', return_value=SimpleNamespace(pw_name='runner')):
            _, _, service = SIGN.require_hosted_fixture()
            self.assertEqual(service, root / 'build/Build/Products/Release/QLReplyProbeProvider.appex'
                             '/Contents/XPCServices/QLReplyProbeXPCService.xpc')
            SIGN.os.environ['TARGET_NAME'] = 'QLReplyProbeContainer'
            with self.assertRaisesRegex(RuntimeError, 'exact hosted Quick Look fixture'):
                SIGN.require_hosted_fixture()

    def test_placement_refuses_missing_or_duplicate_app_level_service(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / 'QLReplyProbeContainer.app'
            provider = app / 'Contents/PlugIns/QLReplyProbeProvider.appex'
            service = provider / 'Contents/XPCServices/QLReplyProbeXPCService.xpc'
            with self.assertRaisesRegex(RuntimeError, 'exactly one extension-level'):
                PREP.validate_service_placement(app, provider)
            service.mkdir(parents=True)
            self.assertEqual(PREP.validate_service_placement(app, provider), service)
            duplicate = app / 'Contents/XPCServices/QLReplyProbeXPCService.xpc'
            duplicate.mkdir(parents=True)
            with self.assertRaisesRegex(RuntimeError, 'exactly one extension-level'):
                PREP.validate_service_placement(app, provider)

    def test_extra_source_right_is_refused_before_codesign(self):
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory)
            (fixture / 'XPCService.entitlements').write_bytes(plistlib.dumps({
                'com.apple.security.app-sandbox': True,
                'com.apple.security.temporary-exception.files.absolute-path.read-only': ['/']}))
            with mock.patch.object(SIGN, 'require_hosted_fixture', return_value=(fixture, fixture, fixture)), \
                    mock.patch.object(SIGN.subprocess, 'run', side_effect=AssertionError('codesign reached')):
                with self.assertRaisesRegex(RuntimeError, 'only the sandbox entitlement'):
                    SIGN.main()

    def test_embedded_copy_is_resigned_and_final_extra_right_is_refused(self):
        sandbox = {'com.apple.security.app-sandbox': True}
        injected = sandbox | {'com.apple.security.temporary-exception.files.absolute-path.read-only': ['/']}
        for after in (sandbox, injected):
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                fixture = root / 'fixture'
                fixture.mkdir()
                source = fixture / 'XPCService.entitlements'
                source.write_bytes(plistlib.dumps(sandbox))
                service = root / 'Provider.appex/Contents/XPCServices/QLReplyProbeXPCService.xpc'
                (service / 'Contents').mkdir(parents=True)
                (service / 'Contents/Info.plist').write_bytes(plistlib.dumps({
                    'CFBundleIdentifier': 'app.mostlytext.QLReplyProbe.XPCService',
                    'XPCService': {'ServiceType': 'Application'}}))
                observed = subprocess.CompletedProcess([], 0, plistlib.dumps(injected), b'')
                signed = subprocess.CompletedProcess([], 0, plistlib.dumps(after), b'')
                with mock.patch.object(SIGN, 'require_hosted_fixture', return_value=(root, fixture, service)), \
                        mock.patch.object(SIGN.subprocess, 'run', side_effect=[observed, None, None, signed]) as calls:
                    if after == sandbox:
                        SIGN.main()
                    else:
                        with self.assertRaisesRegex(RuntimeError, 'only the sandbox entitlement'):
                            SIGN.main()
                self.assertEqual(len(calls.call_args_list), 4)
                sign_command = calls.call_args_list[1].args[0]
                self.assertEqual(sign_command[:6], ['/usr/bin/codesign', '--force', '--sign', '-',
                                                    '--options', 'runtime'])
                self.assertEqual(sign_command[-1], str(service))
                self.assertEqual(sign_command[sign_command.index('--entitlements') + 1], str(source))
                self.assertEqual(plistlib.loads((root / 'xpc-service-after-resign-entitlements.plist').read_bytes()),
                                 after)

    def test_generated_service_embed_precedes_correction_phase(self):
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory) / 'fixture'
            shutil.copytree(FIXTURE, fixture)
            subprocess.run(['xcodegen', 'generate', '--spec', str(fixture / 'project.yml')],
                           capture_output=True, check=True, timeout=60)
            project = fixture / 'QuickLookReplyProbe.xcodeproj/project.pbxproj'
            objects = json.loads(subprocess.check_output(
                ['plutil', '-convert', 'json', '-o', '-', str(project)], timeout=30))['objects']
            provider = next(value for value in objects.values()
                            if value.get('isa') == 'PBXNativeTarget'
                            and value.get('name') == 'QLReplyProbeProvider')
            app = next(value for value in objects.values()
                       if value.get('isa') == 'PBXNativeTarget'
                       and value.get('name') == 'QLReplyProbeContainer')
            phases = [objects[phase] for phase in provider['buildPhases']]
            copies = [position for position, phase in enumerate(phases)
                      if phase['isa'] == 'PBXCopyFilesBuildPhase'
                      and phase.get('dstPath') == '$(CONTENTS_FOLDER_PATH)/XPCServices'
                      and any(objects[objects[item]['fileRef']].get('path') == 'QLReplyProbeXPCService.xpc'
                              for item in phase['files'])]
            scripts = [position for position, phase in enumerate(phases)
                       if phase['isa'] == 'PBXShellScriptBuildPhase'
                       and phase.get('name') == 'Sign embedded XPC service with source entitlements'
                       and phase.get('shellScript') == 'python3 "$SRCROOT/resign-embedded-xpc.py"']
            self.assertEqual(len(copies), 1)
            self.assertEqual(len(scripts), 1)
            self.assertLess(copies[0], scripts[0])
            self.assertEqual(scripts[0], len(phases) - 1)
            self.assertEqual(phases[scripts[0]]['alwaysOutOfDate'], '1')
            self.assertIn('$(TARGET_BUILD_DIR)/$(WRAPPER_NAME)/Contents/XPCServices/'
                          'QLReplyProbeXPCService.xpc/Contents/Info.plist',
                          phases[scripts[0]]['inputPaths'])
            app_phases = [objects[phase] for phase in app['buildPhases']]
            self.assertFalse(any(phase.get('dstPath') == '$(CONTENTS_FOLDER_PATH)/XPCServices'
                                 for phase in app_phases))
            self.assertFalse(any(phase.get('name') == 'Sign embedded XPC service with source entitlements'
                                 for phase in app_phases))


if __name__ == '__main__':
    unittest.main()

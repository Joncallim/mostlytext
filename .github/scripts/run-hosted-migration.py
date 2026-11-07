#!/usr/bin/env python3
"""One fixed normal Release migration/relaunch journey, after a genuine positive."""
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import time

from migration_profile_evidence import editor_width, require_preserved, require_session, sha, snapshot
from native_cli_endpoint_probe import probe_endpoint

SUPPORT = Path('/Users/runner/Library/Application Support')
OLD = SUPPORT / 'MacDown 2'
INSTALL = SUPPORT / 'MostlyText'
STATE = INSTALL / 'installation-v1/State'
PRESERVED = INSTALL / 'installation-v1/Source'
DOMAINS = ['com.joncallim.MacDown2', 'com.joncallim.macdown2.workspace',
           'app.mostlytext.MostlyText', 'app.mostlytext.MostlyText.workspace',
           'com.uranusjr.macdown', 'com.uranusjr.macdown.workspace']


def main():
    spec = importlib.util.spec_from_file_location('migration_preparation', Path(__file__).with_name('prepare-hosted-migration.py'))
    preparation = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(preparation)
    if len(sys.argv) != 1:
        raise RuntimeError('Migration has no caller-selected roots or modes')
    preparation.admit()  # Actual host and qualified ancestry precede receipt/profile reads.
    root = preparation.ROOT
    path = root / 'receipt.json'
    record = json.loads(path.read_text())
    if record.get('migration_qualified_main') != preparation.QUALIFIED_MAIN or record.get('migration_execution_started') is not False:
        raise RuntimeError('Migration receipt is attempted or retargeted')
    record['migration_execution_started'] = True
    current = None
    baseline = None

    def persist():
        path.write_text(json.dumps(record, indent=2) + '\n')

    persist()  # Freeze before even verification/positive commands; never reuse a failed attempt.

    def command(label, args, timeout=30):
        args = [str(a) for a in args]
        result = subprocess.run(args, capture_output=True, timeout=timeout)
        (root / (label + '.stdout')).write_bytes(result.stdout)
        (root / (label + '.stderr')).write_bytes(result.stderr)
        record['commands'].append({'label': label, 'command': args, 'returncode': result.returncode,
                                   'stdout_sha256': sha(result.stdout), 'stderr_sha256': sha(result.stderr)})
        persist()
        if result.returncode:
            raise RuntimeError(label + ' failed: ' + result.stderr.decode(errors='replace')[-4096:])
        return result.stdout

    def verify(label):
        command(label, ['python3', '.github/scripts/prepare-hosted-migration.py', 'verify'], 90)

    def action(operation, identity=None):
        args = [root / 'normal-app-host', operation, record['built']['app']]
        if identity is not None:
            args += [identity['pid'], identity['birth']]
        value = json.loads(command('app-' + operation + '-' + str(len(record.get('applications', []))), args))
        record.setdefault('applications', []).append(value)
        persist()
        return value

    def ui(label, method):
        selected = 'HostedFocusDriverTests/PublicFocusTests/' + method
        control = root / 'control/Build/Products/Release/HostedFocusControl.app/Contents/MacOS/HostedFocusControl'
        args = ['python3', '.github/scripts/run-owned-app-tests.py', str(root / (label + '-owned')), str(control), '--',
                'xcodebuild', '-project', str(root / 'fixture/HostedPublicFocus.xcodeproj'), '-scheme', 'HostedPublicFocus',
                '-configuration', 'Release', '-destination', 'platform=macOS', '-derivedDataPath', str(root / 'control'),
                '-resultBundlePath', str(root / (label + '.xcresult')), '-parallel-testing-enabled', 'NO',
                '-test-timeouts-enabled', 'YES', '-default-test-execution-time-allowance', '120',
                '-maximum-test-execution-time-allowance', '120', '-only-testing:' + selected, 'test-without-building']
        with (root / (label + '.log')).open('w') as log:
            result = subprocess.run(args, stdout=log, stderr=subprocess.STDOUT)
        summary = json.loads(command(label + '-summary', ['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', root / (label + '.xcresult')]))
        owned = json.loads((root / (label + '-owned/status.json')).read_text())
        record.setdefault('ui_results', {})[label] = {'selected': selected, 'summary': summary, 'owned': owned, 'returncode': result.returncode}
        persist()
        expected = {'totalTestCount': 1, 'passedTests': 1, 'failedTests': 0, 'skippedTests': 0, 'expectedFailures': 0}
        log = (root / (label + '.log')).read_text()
        pattern = r"Test Case '-\[HostedFocusDriverTests\.PublicFocusTests " + re.escape(method) + r"\]' "
        if (result.returncode != 0 or owned['returncode'] != 0 or owned['timed_out'] or owned['cancelled']
                or owned['app_cleanup_requested'] or any(type(summary.get(k)) is not int or summary[k] != v for k, v in expected.items())
                or len(re.findall(pattern + 'started', log)) != 1 or len(re.findall(pattern + 'passed', log)) != 1
                or re.search(pattern + 'failed|Restarting after unexpected', log)):
            raise RuntimeError('Uncertain or failed exact migration case: ' + label)
        return True

    def domains(label):
        command('capture-domains-' + label, [record['seed_executable'], '--capture-fixed-domains', label], 60)
        raw = (root / ('migration-domains-' + label + '.plist')).read_bytes()
        rows = plistlib.loads(raw)
        if not isinstance(rows, list) or [r['domain'] for r in rows] != DOMAINS:
            raise RuntimeError('Canonical fixed-domain inventory differs')
        for row in rows:
            if type(row['present']) is not bool or (row['present'] and not isinstance(row.get('value'), dict)):
                raise RuntimeError('Invalid canonical persistent-domain evidence')
        record.setdefault('migration_domain_evidence_sha256', {})[label] = sha(raw)
        persist()
        return {row['domain']: row['value'] if row['present'] else None for row in rows}

    def capture(label):
        trees = {}
        for name, source in [('old', OLD), ('preserved', PRESERVED), ('state', STATE), ('installation', INSTALL)]:
            trees[name] = snapshot(source, root / ('profile-' + label + '-' + name))
        value = {'trees': trees, 'domains': domains(label)}
        (root / ('profile-' + label + '.json')).write_text(json.dumps(trees, indent=2) + '\n')
        # Raw domains are separate original plists; JSON only lists their digests/absence.
        return value

    def validate_after(label, baseline, seed, width):
        captured = capture(label)
        if captured['trees']['old'] != baseline['trees']['old']:
            raise RuntimeError('Original profile identity/mode/bytes changed')
        for domain in DOMAINS[:2] + DOMAINS[4:]:
            if captured['domains'][domain] != baseline['domains'][domain]:
                raise RuntimeError('Original domain changed: ' + domain)
        require_preserved(baseline['trees']['old'], captured['trees']['preserved'])
        if editor_width(captured['domains'][DOMAINS[0]]) != 2 or editor_width(captured['domains'][DOMAINS[2]]) != width:
            raise RuntimeError('Migrated or idempotent indentation differs')
        session = json.loads((STATE / 'session.json').read_bytes())
        require_session(seed, session, STATE)
        recovered = seed['unsavedText'].encode()
        if not any(p.is_file() and p.read_bytes() == recovered for p in (root / ('profile-' + label + '-state/Recovery')).rglob('*')):
            raise RuntimeError('Managed unsaved recovery bytes were not preserved')
        for name in ['snippets.json', 'Themes/migration-fixture.json', 'Commands/must-not-run.command']:
            if sha((STATE / name).read_bytes()) != baseline['trees']['old'][name]['sha256']:
                raise RuntimeError('Migrated seeded data changed: ' + name)
        if (root / 'MIGRATION_COMMAND_RAN').exists() or sha(Path(seed['external']).read_bytes()) != seed['externalSHA256']:
            raise RuntimeError('Command executed or external authored bytes changed')
        record.setdefault('migration_readback', {})[label] = {'original_unchanged': True, 'preserved_complete': True,
                'current_indentation': width, 'old_indentation': 2, 'exact_session_identities_paths_epochs': True,
                'managed_unsaved_recovery_bytes': True, 'seeded_data_and_external_bytes_unchanged': True, 'sentinel_absent': True}
        persist()

    def parent_nodes(label):
        nodes = {}
        for node in [SUPPORT, SUPPORT.parent, Path('/Users/runner')]:
            info = node.lstat()
            nodes[str(node)] = {'mode': info.st_mode, 'uid': info.st_uid, 'gid': info.st_gid,
                                'inode': info.st_ino, 'device': info.st_dev}
        record.setdefault('migration_parent_node_observations', {})[label] = nodes
        persist()

    def wait_peer(identity, label):
        location = Path(subprocess.check_output(['getconf', 'DARWIN_USER_TEMP_DIR'], text=True).strip()).resolve()
        endpoint = location / ('mt-' + hashlib.sha256(b'app.mostlytext.MostlyText').hexdigest()[:24]) / 's'
        deadline = time.monotonic() + 10
        attempts = []
        while time.monotonic() < deadline:
            observed = probe_endpoint(endpoint, identity['pid'], min(0.05, max(0.001, deadline - time.monotonic())))
            attempts.append(observed)
            if observed['ready']:
                break
            time.sleep(min(0.05, max(0, deadline - time.monotonic())))
        record.setdefault('live_endpoints', {})[label] = {'attempts': attempts, 'application_frames_sent': 0}
        persist()
        if not attempts or not attempts[-1]['ready']:
            raise RuntimeError('Normal migration app did not expose the actual peer in10s')

    try:
        verify('before-positive')
        record['criteria']['benign_control'] = ui('positive', 'testBenignInputControl')
        facts = json.loads(command('actual-gui-metadata', [root / 'host-facts']))
        record['actual_gui'] = facts
        if not (facts['on_console'] and facts['login_done'] and facts['screen_lock_field'] is not True
                and facts['keyboard_input_source'] == 'com.apple.keylayout.US' and facts['screens']):
            raise RuntimeError('Actual GUI/US input facts do not admit migration')
        persist()
        verify('after-positive-before-seed')
        parent_nodes('before-seed')
        command('seed-profile', [record['seed_executable']], 60)
        seed = json.loads((root / 'migration-seed.json').read_text())
        baseline = capture('seeded')
        if baseline['trees']['state'] or baseline['trees']['preserved'] or any(baseline['domains'][d] is not None for d in DOMAINS[1:]):
            raise RuntimeError('Fictional profile is not fresh')
        if editor_width(baseline['domains'][DOMAINS[0]]) != 2:
            raise RuntimeError('Canonical development preference was not seeded')
        record['migration_seed_sha256'] = sha((root / 'migration-seed.json').read_bytes())
        persist()
        for label, method, width in [('first', 'testNormalDevelopmentProfileAdoption', 2), ('relaunch', 'testNormalMigratedProfileRelaunch', 8)]:
            verify(label + '-before-launch')
            current = action('launch')
            (root / 'current-application.json').write_text(json.dumps(current, indent=2) + '\n')
            wait_peer(current, label)
            ui(label, method)
            observed = action('inspect', current)
            if any(observed[k] != current[k] for k in ['pid', 'birth', 'executable']):
                raise RuntimeError('Normal process identity changed')
            verify(label + '-before-quit')
            ended = action('terminate', current)
            if not ended['terminated']:
                raise RuntimeError('Normal identity-bound Quit did not finish')
            current = None
            verify(label + '-after-normal-quit')
            validate_after(label, baseline, seed, width)
            if label == 'first':
                record['migration_first_ui_passed'] = True
                record['migration_first_normal_quit_verified'] = True
                persist()
                command('change-current-indentation-only', [record['seed_executable'], '--set-current-indentation-after-first-quit'], 60)
                if sha((root / 'migration-seed.json').read_bytes()) != record['migration_seed_sha256']:
                    raise RuntimeError('Seed oracle changed')
        record['migration_complete'] = True
    except Exception as error:
        record['errors'].append({'type': type(error).__name__, 'message': str(error)[:4096]})
        persist()  # Diagnostic success must never erase or replace this original failure.
        if current is not None:
            try:
                ui('failure-observation', 'testObserveFailedMigrationStartup')
                record['failure_ui_observation_only'] = True
            except Exception as observed:
                record.setdefault('failure_observation_errors', []).append(str(observed)[:4096])
    finally:
        if current is not None:
            try:
                action('inspect', current)
                action('cleanup', current)
                current = None
            except Exception as error:
                record.setdefault('cleanup_errors', []).append(str(error)[:4096])
        if record['errors'] and baseline is not None and current is None:
            try:
                verify('after-failure-cleanup-inputs')
                record['migration_failure_after_source_verified'] = True
                parent_nodes('after-failure-cleanup')
                observed = capture('failure')
                record['migration_failure_original_profile_unchanged'] = observed['trees']['old'] == baseline['trees']['old']
                record['migration_failure_original_domains_unchanged'] = all(
                    observed['domains'][domain] == baseline['domains'][domain] for domain in DOMAINS[:2] + DOMAINS[4:])
                record['migration_failure_command_sentinel_exists'] = (root / 'MIGRATION_COMMAND_RAN').exists()
            except Exception as error:
                record.setdefault('failure_readback_errors', []).append(str(error)[:4096])
        record['passed'] = record.get('migration_complete') is True and not record['errors'] and not record.get('cleanup_errors')
        persist()
    if not record['passed']:
        raise RuntimeError(record['errors'])


if __name__ == '__main__':
    main()

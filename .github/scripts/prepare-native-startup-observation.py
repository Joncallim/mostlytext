#!/usr/bin/env python3
"""Prepare and record three exact, observation-only startup source overlays."""
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys

FILES = {
    "legacy": "MacDown2/Packages/MacDownKit/Sources/AppSettings/LegacyImportStartup.swift",
    "migration": "MacDown2/MacDown2/ApplicationMigrationStartup.swift",
    "delegate": "MacDown2/MacDown2/AppDelegate.swift",
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def observe(component, event):
    return 'observeNative' + component + 'Startup(' + event + ')'


def recipe(kind):
    component = {"legacy": "Legacy", "migration": "Migration", "delegate": "Delegate"}[kind]
    call = lambda event: observe(component, event)
    helper = '''private func observeNativeCOMPONENTStartup(_ event: String) {
    guard FileManager.default.homeDirectoryForCurrentUser.path == "/Users/runner" else { return }
    let record: [String: Any] = ["component": "KIND", "event": event,
                               "pid": ProcessInfo.processInfo.processIdentifier,
                               "time": Date().timeIntervalSince1970]
    guard var bytes = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
          bytes.count <= 2048 else { return }
    bytes.append(0x0A)
    let descriptor = Darwin.open("/Users/runner/work/_temp/native-cli-proof/startup-events.jsonl",
                                O_WRONLY | O_APPEND | O_NOFOLLOW_ANY | O_NONBLOCK | O_CLOEXEC)
    guard descriptor >= 0 else { return }
    defer { Darwin.close(descriptor) }
    var info = stat()
    guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
          info.st_mode & 0o7777 == 0o600, info.st_uid == geteuid(), info.st_nlink == 1,
          info.st_size >= 0, info.st_size <= Int64(65536 - bytes.count) else { return }
    let count = bytes.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
    guard count == bytes.count else { return }
    NSLog("MOSTLYTEXT_STARTUP component=%@ event=%@", "KIND", event)
}

'''.replace("COMPONENT", component).replace("KIND", kind)
    declaration = {"legacy": "@MainActor\n@Observable\npublic final class LegacyImportStartup",
                   "migration": "@MainActor\n@Observable\nfinal class ApplicationMigrationStartup",
                   "delegate": "@MainActor\nfinal class AppDelegate"}[kind]
    edits = [("import Foundation\n", "import Darwin\nimport Foundation\n", 1, False),
             (declaration, helper + declaration, 1, False)]
    if kind == "legacy":
        edits += [
            ("        began = true\n", "        began = true\n        " + call('"begin"') + "\n", 1, False),
            ("            self.journal = journal\n", "            self.journal = journal\n            " + call('"journal-created"') + "\n", 1, False),
            ("            self.bootstrap = bootstrap\n", "            self.bootstrap = bootstrap\n            " + call('"bootstrap-bound"') + "\n", 1, False),
            ("            let result = try await bootstrap.resume(currentSource: source)\n",
             "            let result = try await bootstrap.resume(currentSource: source)\n            " + call('"resume=\\(result)"') + "\n", 1, False),
            ("            let snapshot = try source()\n", "            let snapshot = try source()\n            " + call('"source-entries=\\(snapshot.values.count)"') + "\n", 1, False),
            ("        } catch { phase = .blocked }", "        } catch {\n            " + call('"blocked type=\\(String(reflecting: type(of: error))) domain=\\((error as NSError).domain) code=\\((error as NSError).code)"') + "\n            phase = .blocked\n        }", 3, True),
            ("        await journal?.close()\n", "        " + call('"finish-enter"') + "\n        await journal?.close()\n        " + call('"finish-journal-closed"') + "\n", 1, False),
            ("        phase = .ready\n        didBecomeReady?()", "        phase = .ready\n        " + call('"ready callback=\\(didBecomeReady != nil)"') + "\n        didBecomeReady?()", 1, False),
        ]
    elif kind == "migration":
        edits += [
            ("        } catch { phase = .blocked }", "        } catch {\n            " + call('"blocked type=\\(String(reflecting: type(of: error))) domain=\\((error as NSError).domain) code=\\((error as NSError).code)"') + "\n            phase = .blocked\n        }", 2, True),
            ("        optional.didBecomeReady = { [weak self] in self?.finish() }", "        optional.didBecomeReady = { [weak self] in\n            " + call('"optional-callback self-alive=\\(self != nil)"') + "\n            self?.finish()\n        }", 1, False),
            ("        phase = .optionalImport\n", "        phase = .optionalImport\n        " + call('"optional-initial=\\(optional.phase)"') + "\n", 1, False),
            ("            await optional.begin()\n", "            await optional.begin()\n            " + call('"optional-returned=\\(optional.phase)"') + "\n", 1, False),
            ("    private func finish() {\n", "    private func finish() {\n        " + call('"finish phase=\\(phase) locations=\\(locations != nil) callback=\\(didBecomeReady != nil)"') + "\n", 1, False),
        ]
    else:
        edits += [
            ("    func applicationDidFinishLaunching(_: Notification) {\n", "    func applicationDidFinishLaunching(_: Notification) {\n        " + call('"did-finish phase=\\(startup.phase)"') + "\n", 1, False),
            ("            startup.didBecomeReady = { [weak self] in\n", "            startup.didBecomeReady = { [weak self] in\n                " + call('"startup-callback self-alive=\\(self != nil)"') + "\n", 1, False),
            ("    private func finishApplicationStartup() {\n", "    private func finishApplicationStartup() {\n        " + call('"finish-application normal-ready=\\(normalLaunchReady) phase=\\(startup.phase)"') + "\n", 1, False),
        ]
    return edits


def prepare(repo, output):
    repo = repo.resolve(strict=True)
    assert not output.exists(), "Preserve an existing observation record"
    prepared = {}
    record = {"checkout": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip(),
              "diagnostic_only": True, "complete": False, "files": {}}
    for kind, name in FILES.items():
        path = repo / name
        assert path.resolve(strict=True).is_relative_to(repo) and stat.S_ISREG(path.lstat().st_mode)
        original = subprocess.check_output(["git", "show", "HEAD:" + name], cwd=repo)
        assert path.read_bytes() == original, "Refuse a changed startup source: " + name
        text = original.decode()
        steps = []
        for old, new, count, first_only in recipe(kind):
            assert text.count(old) == count, "Source anchor changed: " + name + " " + old
            text = text.replace(old, new, 1 if first_only else count)
            steps.append({"original": old, "replacement": new, "expected_count": count,
                          "first_only": first_only})
        replacement = text.encode()
        prepared[name] = replacement
        record["files"][name] = {"canonical_sha256": sha(original), "executed_sha256": sha(replacement),
                                  "replacements": steps}
    output.write_text(json.dumps(record, indent=2) + "\n")
    for name, data in prepared.items():
        assert sha((repo / name).read_bytes()) == record["files"][name]["canonical_sha256"]
        (repo / name).write_bytes(data)
    record["complete"] = True
    output.write_text(json.dumps(record, indent=2) + "\n")
    verify(repo, record)
    return record


def verify(repo, record):
    assert record["diagnostic_only"] and record["complete"] and set(record["files"]) == set(FILES.values())
    assert record["checkout"] == subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
    for name, item in record["files"].items():
        kind = next(kind for kind, path in FILES.items() if path == name)
        expected = [{"original": old, "replacement": new, "expected_count": count, "first_only": first_only}
                    for old, new, count, first_only in recipe(kind)]
        assert item["replacements"] == expected, "Refuse an unreviewed observation recipe"
        canonical = subprocess.check_output(["git", "show", record["checkout"] + ":" + name], cwd=repo)
        assert sha(canonical) == item["canonical_sha256"]
        text = canonical.decode()
        for step in item["replacements"]:
            assert text.count(step["original"]) == step["expected_count"]
            text = text.replace(step["original"], step["replacement"], 1 if step["first_only"] else step["expected_count"])
        assert sha(text.encode()) == item["executed_sha256"] == sha((repo / name).read_bytes())


if __name__ == "__main__":
    assert os.environ.get("GITHUB_ACTIONS") == "true" and Path.home() == Path("/Users/runner")
    destination = Path(sys.argv[1]).resolve()
    assert destination.is_relative_to(Path(os.environ["RUNNER_TEMP"]).resolve())
    prepare(Path.cwd(), destination)
    print("Prepared exactly three recorded observation-only source overlays; no production qualification")

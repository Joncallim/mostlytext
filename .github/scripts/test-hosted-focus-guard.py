#!/usr/bin/env python3
"""Actual guard-only before/after controls; no product, preferences or native APIs."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

if sys.flags.optimize:
    raise SystemExit("Run the guard regression controller without optimization")

script = Path(__file__).with_name("prepare-hosted-public-focus.py").resolve()
with tempfile.TemporaryDirectory(prefix="mostlytext-focus-guard-") as temporary:
    root = Path(temporary)
    event = root / "event.json"
    event.write_text(json.dumps({"probe": "owned guard-only event"}))
    environment = dict(os.environ, GITHUB_ACTIONS="false", GITHUB_EVENT_PATH=str(event), GITHUB_EVENT_NAME="workflow_dispatch")
    common = """
import importlib.util, inspect
from pathlib import Path
spec=importlib.util.spec_from_file_location('focus_preparation',SCRIPT)
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
""".replace("SCRIPT", repr(str(script)))
    before = common + """
source=inspect.getsource(module.check_host)
source=source.replace('    if sys.flags.optimize:\\n        raise RuntimeError("Optimized Python cannot enforce this hosted execution contract")\\n','')
namespace=dict(module.__dict__)
exec(compile(source,'<assertion-only-guard-before>','exec'),namespace)
namespace['check_host'](Path(ROOT))
print('OLD_GUARD_ACCEPTED_UNTRUSTED_CONTEXT')
""".replace("ROOT", repr(str(root / "not-created")))
    result = subprocess.run([sys.executable, "-O", "-c", before], env=environment, capture_output=True, text=True, timeout=15)
    assert result.returncode == 0 and "OLD_GUARD_ACCEPTED_UNTRUSTED_CONTEXT" in result.stdout, result.stderr
    after = common + "module.check_host(Path(" + repr(str(root / "not-created")) + "))\n"
    for flags in [[], ["-O"]]:
        result = subprocess.run([sys.executable, *flags, "-c", after], env=environment, capture_output=True, text=True, timeout=15)
        assert result.returncode != 0
        assert ("Optimized Python cannot enforce" in result.stderr) if flags else ("AssertionError" in result.stderr)
    assert sorted(p.name for p in root.iterdir()) == ["event.json"]
print("Three guard-only controls pass: assertion-only -O counterexample; corrected normal/optimized refusals. No native execution or preference access.")

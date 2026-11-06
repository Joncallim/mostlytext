#!/usr/bin/env python3
"""Pure controls for exact reviewed dependency updates; never execute native code."""
import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("model_probe", Path(__file__).with_name("run-attachment-publication-probe.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def pin(identity, owner, revision):
    return {"identity": identity, "location": owner, "state": {"revision": revision}}


class ExactPinReviewTests(unittest.TestCase):
    def setUp(self):
        self.before = [pin("textual", "https://github.com/Joncallim/textual", "c52cb5834c4695109aad2cb66294eafbc8f264c8")]
        for name, (owner, previous, _) in module.REVIEWED_INDEPENDENT_PIN_UPDATES.items():
            self.before.append(pin(name, owner, previous))
        self.after = copy.deepcopy(self.before)
        self.after[0]["state"]["revision"] = "dd123d4f7052d84032cafb22c62cd467916518dd"

    def apply_reviewed_updates(self, pins):
        for value in pins:
            if value["identity"] in module.REVIEWED_INDEPENDENT_PIN_UPDATES:
                value["state"]["revision"] = module.REVIEWED_INDEPENDENT_PIN_UPDATES[value["identity"]][2]

    def test_original_model_only_change_keeps_the_original_constraint(self):
        self.assertEqual(module.reviewed_model_pin_delta(self.before, self.after), (True, {}))

    def test_exact_reviewed_updates_are_recorded_with_both_immutable_versions(self):
        self.apply_reviewed_updates(self.after)
        model_changed, recorded = module.reviewed_model_pin_delta(self.before, self.after)
        self.assertTrue(model_changed)
        self.assertEqual(set(recorded), {"neon", "swifttreesitter"})
        for name, (owner, previous, candidate) in module.REVIEWED_INDEPENDENT_PIN_UPDATES.items():
            self.assertEqual(recorded[name], {"original": (owner, previous), "candidate": (owner, candidate)})

    def test_unreviewed_revisions_owners_removals_and_new_pins_are_rejected(self):
        cases = []
        changed = copy.deepcopy(self.after)
        changed[1]["state"]["revision"] = "0" * 40
        cases.append(changed)
        changed = copy.deepcopy(self.after)
        changed[1]["location"] = "https://github.com/other/Neon"
        cases.append(changed)
        changed = copy.deepcopy(self.after)
        changed[0]["location"] = "https://github.com/other/textual"
        cases.append(changed)
        cases.append(self.after[1:])
        cases.append(self.after[:-1])
        cases.append(self.after + [pin("new-library", "https://github.com/other/new", "1" * 40)])
        for changed in cases:
            with self.subTest(changed=changed), self.assertRaises(SystemExit):
                module.reviewed_model_pin_delta(self.before, changed)

    def test_independent_updates_cannot_qualify_an_unchanged_original_model(self):
        current = copy.deepcopy(self.before)
        self.apply_reviewed_updates(current)
        model_changed, independent = module.reviewed_model_pin_delta(self.before, current)
        self.assertFalse(model_changed)
        self.assertEqual(set(independent), {"neon", "swifttreesitter"})


if __name__ == "__main__":
    unittest.main()

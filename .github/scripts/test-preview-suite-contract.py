#!/usr/bin/env python3
"""Match real Swift test methods to both native controllers before any native work."""
import ast
from pathlib import Path
import re
from types import SimpleNamespace
import unittest

SCRIPTS = Path(__file__).parent
TESTS = SCRIPTS.parents[1] / 'MacDown2/MacDown2Tests'
COPY = 'aNoWriteNativeCopyCannotReuseAnEarlierImage'


def mounted_functions():
    files = list(TESTS.glob('SecuredMarkdownMountedTests*.swift'))
    source = '\n'.join(p.read_text() for p in files)
    functions = re.findall(r'@Test\s+func\s+(\w+)\(', source)
    if len(re.findall(r'@Test\b', source)) != len(functions):
        raise ValueError('An unrecognized Swift Test declaration requires explicit catalog review')
    if not functions or len(set(functions)) != len(functions) or COPY not in functions:
        raise ValueError('Require unique actual mounted functions including fresh clipboard ownership')
    return set(functions)


def check_experiments(tree, functions):
    assignments = [n for n in ast.walk(tree) if isinstance(n, ast.Assign)
                   and any(isinstance(t, ast.Name) and t.id == 'experiments' for t in n.targets)
                   and isinstance(n.value, ast.List)]
    if len(assignments) != 1:
        raise ValueError('Require the actual fixed six experiment records')
    found = set()
    for row in assignments[0].value.elts:
        name, suite, count = (ast.literal_eval(row.elts[i]) for i in [0, 2, 3])
        found.add(name)
        expected = len(functions) if suite == 'SecuredMarkdownMountedTests' else 1
        if count != expected:
            raise ValueError('Native experiment omits actual Swift methods: ' + name)
    if found != {p + '-' + state for p in ['revision', 'viewport', 'disappear'] for state in ['mutant', 'restored']}:
        raise ValueError('An original mutation/restoration pair is missing')


def count_expression(tree):
    values = [n.value for n in ast.walk(tree) if isinstance(n, ast.Assign)
              and any(isinstance(t, ast.Name) and t.id == 'count' for t in n.targets)
              and any(isinstance(v, ast.Name) and v.id == 'phase' for v in ast.walk(n.value))]
    if len(values) != 1:
        raise ValueError('Require the actual result-count policy')
    return values[0]


def check_result_policy(expression, functions):
    # This is the repository's own pure count expression, not externally supplied code.
    code = compile(ast.Expression(expression), '<native-count-policy>', 'eval')
    for configuration in ['Debug', 'Release']:
        for pair in ['revision', 'viewport', 'disappear']:
            for phase in ['selection', pair + '-mutant', pair + '-restored']:
                actual = eval(code, {'__builtins__': {}}, {'args': SimpleNamespace(configuration=configuration, pair=pair), 'phase': phase})
                expected = 1 if phase == 'selection' or pair == 'viewport' else len(functions)
                if actual != expected:
                    raise ValueError('Actual result policy omits mounted functions: ' + phase)


class SuiteContract(unittest.TestCase):
    def setUp(self):
        self.functions = mounted_functions()
        self.experiments = ast.parse((SCRIPTS / 'check-preview-parsed-frame.py').read_text())
        self.results = ast.parse((SCRIPTS / 'verify-preview-grant-probe.py').read_text())

    def test_both_actual_native_controllers_cover_the_real_swift_suite(self):
        check_experiments(self.experiments, self.functions)
        check_result_policy(count_expression(self.results), self.functions)

    def test_previous_three_function_experiments_are_refused(self):
        class PreviousCount(ast.NodeTransformer):
            def visit_Constant(self, node):
                return ast.copy_location(ast.Constant(len(self.functions) - 1), node) if node.value == len(self.functions) else node
        changer = PreviousCount()
        changer.functions = self.functions
        changed = changer.visit(self.experiments)
        with self.assertRaises(ValueError):
            check_experiments(changed, self.functions)

    def test_previous_three_function_result_policy_is_refused(self):
        expression = count_expression(self.results)
        class PreviousCount(ast.NodeTransformer):
            def visit_Constant(inner, node):
                return ast.copy_location(ast.Constant(len(self.functions) - 1), node) if node.value == len(self.functions) else node
        changed = ast.fix_missing_locations(PreviousCount().visit(expression))
        with self.assertRaises(ValueError):
            check_result_policy(changed, self.functions)

    def test_fresh_clipboard_positive_is_required_in_each_unaffected_list(self):
        rows = [n for n in ast.walk(self.experiments) if isinstance(n, ast.Dict)
                and any(isinstance(k, ast.Constant) and k.value == 'revision-mutant' for k in n.keys)]
        self.assertEqual(len(rows), 1)
        values = ast.literal_eval(rows[0])
        for pair in ['revision-mutant', 'disappear-mutant']:
            self.assertEqual(set(values[pair]), self.functions - ({'aNewParsedRevisionReplacesTheLoadWithoutAnotherModelEdit'} if pair == 'revision-mutant' else {'hidingDuringAParsedFrameReplacementRevokesTheRetainedLoader'}))


if __name__ == '__main__':
    unittest.main()

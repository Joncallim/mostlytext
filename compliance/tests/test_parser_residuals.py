"""Refuse changed residual identities, syntax evidence and false rights clearance."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

TOOLS=Path(__file__).resolve().parents[1]/'tools'
sys.path.insert(0,str(TOOLS))
import verify_parser_residuals as residuals


class ParserResidualTests(unittest.TestCase):
    def setUp(self):
        self.root=TOOLS.parents[1]
        self.data=json.loads((self.root/residuals.PACKET/'classification.json').read_text())
        self.parent=json.loads((self.root/residuals.PARENT/'classification.json').read_text())
        self.original=json.loads((self.root/residuals.INDEX).read_text())

    def check(self,data=None,parent=None,original=None):
        residuals.validate_receipt(data or self.data,parent or self.parent,original or self.original)

    def test_current_exact_receipt_passes_all_parent_bindings(self):
        residuals.verify_installed(self.root)

    def test_missing_duplicate_and_reordered_residual_rows_fail(self):
        for kind in ['missing','duplicate','reordered']:
            data=copy.deepcopy(self.data)
            if kind=='missing':data['positions'].pop()
            elif kind=='duplicate':data['positions'][1]=data['positions'][0]
            else:data['positions'][0:2]=reversed(data['positions'][0:2])
            with self.subTest(kind=kind),self.assertRaises(ValueError):self.check(data)

    def test_changed_original_member_coordinate_and_outer_binding_fail(self):
        for key,new in [('parser_member_sha256','0'*64),('parser_utf16_column',999),('outer_generated_positions',[[1,1]])]:
            original=copy.deepcopy(self.original)
            original['positions'][self.data['positions'][0]['original_row_index']][key]=new
            with self.subTest(key=key),self.assertRaisesRegex(ValueError,'identity changed'):self.check(original=original)

    def test_previously_classified_rows_cannot_replace_the_residual_selection(self):
        data=copy.deepcopy(self.data)
        data['positions'][0].update(self.parent['positions'][0])
        with self.assertRaisesRegex(ValueError,'row binding'):self.check(data)

    def test_false_clearance_wrong_parent_tool_or_boolean_counts_fail(self):
        for key,new in [('independent_review_required',False),('reviewed_references',True),
                        ('remaining_technically_unclassified',False),('parent_classification_sha256','0'*64),
                        ('parser_controls',1),('parser','acorn@0.0.0')]:
            data=dict(self.data,**{key:new})
            with self.subTest(key=key),self.assertRaises(ValueError):self.check(data)
        with self.assertRaises(ValueError):self.check(dict(self.data,rights_cleared=True))

    def test_unsupported_or_mismatched_token_node_category_fails(self):
        for key,new in [('category','cleared'),('node_type','Literal'),('token_type','string')]:
            data=copy.deepcopy(self.data);data['positions'][0][key]=new
            with self.subTest(key=key),self.assertRaisesRegex(ValueError,'Unsupported'):self.check(data)

    def test_invalid_span_digests_and_support_containment_fail(self):
        for key,new in [('token_span',[True,2]),('node_span',[-1,2]),('token_span',[0,99999999]),
                        ('token_sha256','altered'),('node_sha256','0'*63)]:
            data=copy.deepcopy(self.data);data['positions'][0][key]=new
            with self.subTest(key=key),self.assertRaises(ValueError):self.check(data)

    def test_category_totals_cannot_hide_a_partial_or_relabelled_result(self):
        data=copy.deepcopy(self.data);data['positions'][0]['category']='closing-array-delimiter'
        with self.assertRaises(ValueError):self.check(data)
        data=copy.deepcopy(self.data);data['categories']['closing-object-delimiter']=True
        with self.assertRaises(ValueError):self.check(data)

    def test_missing_pinned_packet_fails(self):
        with tempfile.TemporaryDirectory() as folder,self.assertRaisesRegex(ValueError,'proof missing'):
            residuals.verify_installed(Path(folder))


if __name__=='__main__':unittest.main()

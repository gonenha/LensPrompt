import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

MODULE = Path(__file__).parents[1] / 'lensprompt-script/scripts/send_script.py'
_spec = importlib.util.spec_from_file_location('sender', MODULE)
sender = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sender)

PAYLOAD = {'version': 1, 'id': '081ec4e6-3884-40c3-936a-05597a111111', 'title': 'תסריט',
           'text': 'טקסט מלא', 'points': {'opening': 'פתיח', 'pain': 'כאב', 'solution': 'פתרון', 'offer': 'הצעה'}, 'mode': 'scrolling'}

class SenderTests(unittest.TestCase):
    def test_rejects_unsafe_ids_versions_and_missing_points(self):
        for change in [{'id': '../escape'}, {'version': True}, {'version': 2}, {'title': '  '}, {'text': '\u0000'}, {'points': {'opening': 'one'}}]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                sender.validate(json.dumps(PAYLOAD | change).encode())
        value, digest = sender.validate(json.dumps(PAYLOAD, ensure_ascii=False).encode())
        self.assertEqual(value['title'], 'תסריט')
        self.assertEqual(len(digest), 64)

    def test_changed_content_never_reaches_transport(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'approved.json'
            original = json.dumps(PAYLOAD).encode()
            _, approved = sender.validate(original)
            path.write_bytes(json.dumps(PAYLOAD | {'title': 'changed'}).encode())
            with patch.object(sender, 'deliver') as transport:
                with self.assertRaises(ValueError):
                    sender.send(path, approved, device='test', simulator=None, wait=0)
                transport.assert_not_called()

    def test_receipt_must_match_exact_id_and_hash(self):
        receipt = {'version': 1, 'id': PAYLOAD['id'].upper(), 'sha256': 'a' * 64, 'status': 'imported'}
        self.assertTrue(sender.receipt_matches(receipt, PAYLOAD['id'], 'a' * 64))
        self.assertFalse(sender.receipt_matches(receipt, PAYLOAD['id'], 'b' * 64))
        self.assertFalse(sender.receipt_matches(receipt | {'id': 'wrong'}, PAYLOAD['id'], 'a' * 64))

if __name__ == '__main__':
    unittest.main()

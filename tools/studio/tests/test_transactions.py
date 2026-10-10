import base64
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import serve

class Transactions(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name).resolve()
        (self.root / 'data').mkdir()
        (self.root / 'assets/audio').mkdir(parents=True)
        (self.root / 'data/original.json').write_text('{"damage":12}')
        (self.root / 'assets/audio/untouched.wav').write_bytes(b'untouched audio')
        self.patcher = patch.object(serve, 'ROOT', self.root)
        self.patcher.start()
    def tearDown(self):
        self.patcher.stop()
        self.tmp.cleanup()
    def row(self, path, raw):
        return {'path':path,'b64':base64.b64encode(raw).decode()}
    def test_all_bytes_validated_before_first_write(self):
        with self.assertRaises(ValueError):
            serve.apply_changes([self.row('data/original.json',b'{"damage":7}'),self.row('data/broken.json',b'{broken')],[])
        self.assertEqual(json.loads((self.root/'data/original.json').read_text()),{'damage':12})
        self.assertFalse((self.root/'data/broken.json').exists())
    def test_failure_rolls_back_new_files_deleted_files_and_generator_outputs(self):
        rows=[self.row('data/new.json',b'{}')]
        with self.assertRaises(RuntimeError):
            with serve.write_transaction(rows,['data/original.json']):
                serve.apply_changes(rows,['data/original.json'])
                (self.root/'data/generated.json').write_text('{}')
                raise RuntimeError('generator failed')
        self.assertFalse((self.root/'data/new.json').exists())
        self.assertFalse((self.root/'data/generated.json').exists())
        self.assertEqual(json.loads((self.root/'data/original.json').read_text()),{'damage':12})
        self.assertEqual((self.root/'assets/audio/untouched.wav').read_bytes(),b'untouched audio')
    def test_nonfinite_json_and_invalid_png_are_rejected(self):
        for raw,path in [(b'{"damage":NaN}','data/a.json'),(b'not a picture','assets/a.png')]:
            with self.assertRaises(Exception): serve.apply_changes([self.row(path,raw)],[])
            self.assertFalse((self.root/path).exists())
    def test_generator_scope_excludes_unrelated_audio(self):
        (self.root/'tools/studio/overrides').mkdir(parents=True)
        with self.assertRaises(RuntimeError):
            rows=[self.row('tools/studio/overrides/overrides.json',b'{}')]
            with serve.write_transaction(rows,[]) as before:
                self.assertNotIn(self.root/'assets/audio/untouched.wav',before)
                serve.apply_changes(rows,[])
                raise RuntimeError('rollback')
        self.assertEqual((self.root/'assets/audio/untouched.wav').read_bytes(),b'untouched audio')

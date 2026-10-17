import gzip
import pathlib
import tempfile
import unittest
from analyze_log import analyze


class LogEvidenceTests(unittest.TestCase):
    def test_multiple_boot_versions_and_shutdown_are_not_root_cause(self):
        content = ('RPCS3 v0.0.43-20288-ce107789 Alpha | master\n'
                   '·! 0:00:41.0 SYS: Serial: BCUS98114\n'
                   '·! 0:00:41.1 SYS: Version: APP_VER=01.00 VERSION=04.00\n'
                   '·! 0:00:41.2 SYS: Version: APP_VER=01.13 VERSION=01.00\n'
                   '·E 0:25:10.1 {Emulation Join Thread} SIG: Thread [rsx::thread] is too sleepy. Waiting for it 17000us already!\n'
                   '> 0001fc04: 24 3c 00 87 stqd r7,0xf00(sp)\n')
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / 'RPCS3.log'
            path.write_text(content, encoding='utf-8')
            result = analyze(path)['evidence']
            self.assertEqual(result['serials'], ['BCUS98114'])
            self.assertEqual(len(result['game_versions']), 2)
            self.assertEqual(len(result['rsx_shutdown_waits']), 1)
            self.assertEqual(result['memory_errors'], [])
            self.assertEqual(result['fatal'], [])

    def test_gzip_explicit_oom_is_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / 'RPCS3.log.gz'
            with gzip.open(path, 'wt', encoding='utf-8') as file:
                file.write('·F 0:03:00.0 RSX: VK_ERROR_OUT_OF_DEVICE_MEMORY\n')
            result = analyze(path)['evidence']
            self.assertEqual(len(result['memory_errors']), 1)
            self.assertEqual(len(result['fatal']), 1)


if __name__ == '__main__':
    unittest.main()

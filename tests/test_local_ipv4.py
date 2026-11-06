"""Exercise the shared IPv4 selector without DNS or network access."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class LocalIPv4Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory(prefix='local-ipv4-tests-')
        cls.host = Path(cls.build.name) / 'host'
        subprocess.run(['xcrun', '--sdk', 'macosx', 'clang', '-fobjc-arc',
                        '-I', str(ROOT / 'src'), str(ROOT / 'tests/local_ipv4_host.m'),
                        '-framework', 'Foundation', '-o', str(cls.host)], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.build.cleanup()

    def select(self, interfaces, **options):
        body = {'interfaces': interfaces, **options}
        return subprocess.check_output([str(self.host), json.dumps(body)], text=True)

    def test_route_source_wins_over_interface_priority(self):
        self.assertEqual(self.select([{'name': 'en2', 'ip': '192.168.2.2'}], probe='192.168.1.2'), '192.168.1.2')

    def test_fallback_order_does_not_depend_on_enumeration_order(self):
        other = {'name': 'bridge0', 'ip': '192.168.3.2'}
        wifi = {'name': 'en0', 'ip': '192.168.1.2'}
        usb = {'name': 'en2', 'ip': '192.168.2.2'}
        for entries in [[other, wifi, usb], [usb, other, wifi], [wifi, usb, other]]:
            self.assertEqual(self.select(entries), usb['ip'])
        self.assertEqual(self.select([other, wifi]), wifi['ip'])
        self.assertEqual(self.select([other]), other['ip'])

    def test_failed_probe_falls_back(self):
        entries = [{'name': 'en2', 'ip': '192.168.2.2'}]
        self.assertEqual(self.select(entries, probe='10.0.0.2', connect_fails=True), '192.168.2.2')
        self.assertEqual(self.select(entries, probe='0.0.0.0'), '192.168.2.2')

    def test_unusable_interfaces_do_not_hide_usable_lower_priority(self):
        for invalid in [{'ip': '0.0.0.0'}, {'ip': '127.0.0.1'}, {'ip': '169.254.1.2'},
                        {'ip': '224.0.0.1'}, {'ip': '192.168.2.2', 'down': True},
                        {'ip': '192.168.2.2', 'loopback': True}]:
            with self.subTest(invalid=invalid):
                self.assertEqual(self.select([{'name': 'en2', **invalid},
                                              {'name': 'en0', 'ip': '192.168.1.2'}]), '192.168.1.2')

    def test_no_usable_address(self):
        self.assertEqual(self.select([]), '')
        self.assertEqual(self.select([], interfaces_fail=True), '')

"""Exercise the production setup function with mocked RFB and address selection."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BindStartupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory(prefix='trollvnc-bind-tests-')
        cls.host = Path(cls.build.name) / 'host'
        source = (ROOT / 'src/trollvncserver.mm').read_text()
        classifier = source[source.index('typedef NS_ENUM(uint8_t, TVBindHostKind)'):
                            source.index('NS_INLINE BOOL isRepeaterEnabled')]
        setup = source[source.index('static void setupRfbScreen('):
                       source.index('static void setupRfbEventHandlers(')]
        prefix = r'''#import <Foundation/Foundation.h>
#import <arpa/inet.h>
#import <rfb/rfb.h>
#include <cstdio>
#include <cstdlib>
static rfbScreenInfoPtr gScreen;
static int gWidth=1, gHeight=1, gBytesPerPixel=4, gPort=15901;
static char frame[4];
static char *gFrontBuffer=frame;
static NSString *gDesktopName=@"test", *gBindHost;
static BOOL gBindAutoIPv4=NO, reverseMode=NO;
static int queries=0, waits=0;
static BOOL isRepeaterEnabled(void) { return reverseMode; }
static NSString *JBLocalIPv4Address(void) {
    ++queries;
    const char *value=getenv("TEST_IP");
    return value && *value ? @(value) : nil;
}
static unsigned int testSleep(unsigned int seconds) {
    if (++waits == 3) exit(77);
    return 0;
}
static rfbScreenInfoPtr hostGetScreen(int*,char**,int,int,int,int,int) {
    static rfbScreenInfo screen={0}; return &screen;
}
static decltype(gScreen->newClientHook) newClientHook=nullptr;
static decltype(gScreen->displayHook) displayHook=nullptr;
static decltype(gScreen->displayFinishedHook) displayFinishedHook=nullptr;
static decltype(gScreen->setDesktopSizeHook) setDesktopSizeHook=nullptr;
#define TVLog(...) ((void)0)
#define TVPrintError(...) ((void)0)
#define rfbGetScreen hostGetScreen
#define sleep testSleep
'''
        suffix = r'''
int main(int argc, char **argv) { @autoreleasepool {
    gBindHost=@(argv[1]); reverseMode=atoi(argv[2]) != 0;
    setenv("TEST_IP", argv[3], 1);
    if(reverseMode) gPort=-1;
    setupRfbScreen(0,nullptr);
    struct in_addr addr={gScreen->listenInterface};
    printf("%s %d %d %d", inet_ntoa(addr), gScreen->ipv6port, queries, waits);
} }
'''
        path = Path(cls.build.name) / 'host.mm'
        path.write_text(prefix + classifier + setup + suffix)
        subprocess.run(['xcrun', '--sdk', 'macosx', 'clang++', '-fobjc-arc', '-std=c++20',
                        '-I', str(ROOT / 'include'), str(path), '-framework', 'Foundation',
                        '-o', str(cls.host)], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.build.cleanup()

    def run_host(self, bind, reverse, ip):
        return subprocess.run([str(self.host), bind, str(int(reverse)), ip], capture_output=True, text=True)

    def test_auto_and_legacy_en0_use_selected_address_and_disable_ipv6(self):
        for bind in ['auto', 'en0']:
            for address in ['192.168.2.2', '192.168.1.2', '10.0.0.2']:
                with self.subTest(bind=bind, address=address):
                    result = self.run_host(bind, False, address)
                    self.assertEqual(result.returncode, 0)
                    self.assertEqual(result.stdout, address + ' -1 1 0')

    def test_reverse_does_not_probe_or_wait_without_local_address(self):
        for bind in ['auto', 'en0']:
            result = self.run_host(bind, True, '')
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout, '0.0.0.0 -1 0 0')

    def test_forward_waits_if_no_address_instead_of_listening_on_all_interfaces(self):
        self.assertEqual(self.run_host('auto', False, '').returncode, 77)

    def test_literal_and_empty_bind_do_not_probe(self):
        for bind, address in [('192.168.9.2', '192.168.9.2'), ('', '0.0.0.0')]:
            result = self.run_host(bind, False, '')
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout, address + ' 15901 0 0')

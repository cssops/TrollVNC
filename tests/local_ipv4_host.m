#import <Foundation/Foundation.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <netdb.h>
#import <sys/socket.h>
#import <unistd.h>

static NSDictionary *fixture;
static int TestResolve(const char *host, const char *port, const struct addrinfo *hints, struct addrinfo **out) {
    if (![fixture[@"probe"] length]) return EAI_NONAME;
    static struct addrinfo result;
    static struct sockaddr_in destination;
    result.ai_family = AF_INET;
    result.ai_socktype = SOCK_DGRAM;
    result.ai_protocol = IPPROTO_UDP;
    result.ai_addr = (struct sockaddr *)&destination;
    result.ai_addrlen = sizeof(destination);
    *out = &result;
    return 0;
}
static void TestFreeAddresses(struct addrinfo *addresses) {}
static int TestSocket(int domain, int type, int protocol) { return 123; }
static int TestConnect(int fd, const struct sockaddr *address, socklen_t length) {
    return [fixture[@"connect_fails"] boolValue] ? -1 : 0;
}
static int TestSocketName(int fd, struct sockaddr *address, socklen_t *length) {
    struct sockaddr_in *local = (struct sockaddr_in *)address;
    local->sin_family = AF_INET;
    return inet_pton(AF_INET, [fixture[@"probe"] UTF8String], &local->sin_addr) == 1 ? 0 : -1;
}
static int TestClose(int fd) { return 0; }
static int TestInterfaces(struct ifaddrs **out) {
    if ([fixture[@"interfaces_fail"] boolValue]) return -1;
    struct ifaddrs **next = out;
    for (NSDictionary *entry in fixture[@"interfaces"]) {
        struct ifaddrs *node = calloc(1, sizeof(*node));
        node->ifa_name = strdup([entry[@"name"] UTF8String]);
        node->ifa_flags = IFF_UP | IFF_RUNNING;
        if ([entry[@"down"] boolValue]) node->ifa_flags = 0;
        if ([entry[@"loopback"] boolValue]) node->ifa_flags |= IFF_LOOPBACK;
        struct sockaddr_in *address = calloc(1, sizeof(*address));
        address->sin_family = AF_INET;
        inet_pton(AF_INET, [entry[@"ip"] UTF8String], &address->sin_addr);
        node->ifa_addr = (struct sockaddr *)address;
        *next = node;
        next = &node->ifa_next;
    }
    *next = NULL;
    return 0;
}
static void TestFreeInterfaces(struct ifaddrs *interfaces) {
    while (interfaces) {
        struct ifaddrs *next = interfaces->ifa_next;
        free(interfaces->ifa_name);
        free(interfaces->ifa_addr);
        free(interfaces);
        interfaces = next;
    }
}
#define getaddrinfo TestResolve
#define freeaddrinfo TestFreeAddresses
#define socket TestSocket
#define connect TestConnect
#define getsockname TestSocketName
#define close TestClose
#define getifaddrs TestInterfaces
#define freeifaddrs TestFreeInterfaces
#import "LocalIPv4.h"

int main(int argc, char **argv) {
    @autoreleasepool {
        NSData *data = [@(argv[1]) dataUsingEncoding:NSUTF8StringEncoding];
        fixture = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *ip = JBLocalIPv4Address();
        printf("%s", ip.UTF8String ?: "");
    }
}

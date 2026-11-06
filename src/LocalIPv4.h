#pragma once
#import <Foundation/Foundation.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <netdb.h>
#import <sys/socket.h>
#import <unistd.h>
#import <string.h>

static inline NSString *JBUsableIPv4Address(const struct sockaddr_in *address) {
    if (!address || address->sin_family != AF_INET) return nil;
    uint32_t host = ntohl(address->sin_addr.s_addr);
    if (!host || (host >> 24) == 127 || (host >> 16) == 0xA9FE || host >= 0xE0000000U) return nil;
    char buffer[INET_ADDRSTRLEN];
    return inet_ntop(AF_INET, &address->sin_addr, buffer, sizeof(buffer)) ? @(buffer) : nil;
}

static inline NSString *JBProbeOutboundIPv4Address(void) {
    // UDP connect selects a route/source without sending application data.
    struct addrinfo hints = {0};
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_DGRAM;
    hints.ai_protocol = IPPROTO_UDP;
    hints.ai_flags = AI_NUMERICSERV;
    struct addrinfo *addresses = NULL;
    if (getaddrinfo("www.apple.com", "443", &hints, &addresses) != 0) return nil;
    NSString *ip = nil;
    for (struct addrinfo *entry = addresses; entry; entry = entry->ai_next) {
        int fd = socket(entry->ai_family, entry->ai_socktype, entry->ai_protocol);
        if (fd < 0) continue;
        struct sockaddr_in local = {0};
        socklen_t length = sizeof(local);
        BOOL selected = connect(fd, entry->ai_addr, entry->ai_addrlen) == 0 &&
                        getsockname(fd, (struct sockaddr *)&local, &length) == 0;
        close(fd);
        if (selected) ip = JBUsableIPv4Address(&local);
        if (ip) break;
    }
    freeaddrinfo(addresses);
    return ip;
}

// Prefer the outbound source; offline fallback: en2 > en0 > other usable interfaces.
static inline NSString *JBLocalIPv4Address(void) {
    NSString *outbound = JBProbeOutboundIPv4Address();
    if (outbound) return outbound;
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) != 0) return nil;
    NSString *ip = nil;
    int bestPriority = -1;
    for (struct ifaddrs *entry = interfaces; entry; entry = entry->ifa_next) {
        if (!entry->ifa_name || !entry->ifa_addr || entry->ifa_addr->sa_family != AF_INET ||
            (entry->ifa_flags & (IFF_UP | IFF_RUNNING)) != (IFF_UP | IFF_RUNNING) ||
            (entry->ifa_flags & IFF_LOOPBACK)) continue;
        NSString *candidate = JBUsableIPv4Address((const struct sockaddr_in *)entry->ifa_addr);
        if (!candidate) continue;
        int priority = strcmp(entry->ifa_name, "en2") == 0 ? 2 :
                       strcmp(entry->ifa_name, "en0") == 0 ? 1 : 0;
        if (priority > bestPriority) {
            ip = candidate;
            bestPriority = priority;
        }
        if (bestPriority == 2) break;
    }
    freeifaddrs(interfaces);
    return ip;
}

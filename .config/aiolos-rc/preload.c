/* aiolos-rc LD_PRELOAD redirect.
 *
 * Per-process, no-root way to make ONLY the claude process reach the local
 * aiolos-rc shim instead of the real api.anthropic.com, without the unix socket
 * (which would flip Claude into host-managed auth mode and break remote control).
 *
 *   getaddrinfo("api.anthropic.com", ...) -> resolve the sentinel 127.0.0.2
 *   connect(fd, 127.0.0.2:*)              -> rewrite to 127.0.0.1:$AIOLOS_RC_PORT
 *
 * Claude still uses SNI/host "api.anthropic.com" (so the shim's cert, trusted via
 * NODE_EXTRA_CA_CERTS, validates) and stays in normal login mode, so RC works.
 * The shim runs in a separate process WITHOUT this preload, so its own outbound
 * DNS/connections resolve normally.
 *
 * Build: gcc -shared -fPIC -O2 -o preload.so preload.c -ldl
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <netdb.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <string.h>
#include <stdlib.h>
#include <sys/socket.h>

#define SENTINEL "127.0.0.2"
static const char *TARGET_HOST = "api.anthropic.com";

static int shim_port(void) {
    const char *p = getenv("AIOLOS_RC_PORT");
    return p ? atoi(p) : 0;
}

typedef int (*getaddrinfo_fn)(const char *, const char *, const struct addrinfo *, struct addrinfo **);
typedef int (*connect_fn)(int, const struct sockaddr *, socklen_t);

int getaddrinfo(const char *node, const char *service,
                const struct addrinfo *hints, struct addrinfo **res) {
    static getaddrinfo_fn real = NULL;
    if (!real) real = (getaddrinfo_fn)dlsym(RTLD_NEXT, "getaddrinfo");
    if (node && strcasecmp(node, TARGET_HOST) == 0) {
        /* Resolve the sentinel loopback address instead. Keep the same service
         * and hints so port/socktype selection is unchanged. */
        return real(SENTINEL, service, hints, res);
    }
    return real(node, service, hints, res);
}

int connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    static connect_fn real = NULL;
    if (!real) real = (connect_fn)dlsym(RTLD_NEXT, "connect");
    int port = shim_port();
    if (port > 0 && addr && addr->sa_family == AF_INET) {
        const struct sockaddr_in *in = (const struct sockaddr_in *)addr;
        struct in_addr sentinel;
        inet_aton(SENTINEL, &sentinel);
        if (in->sin_addr.s_addr == sentinel.s_addr) {
            struct sockaddr_in redir = *in;
            inet_aton("127.0.0.1", &redir.sin_addr);
            redir.sin_port = htons((unsigned short)port);
            return real(sockfd, (const struct sockaddr *)&redir, sizeof(redir));
        }
    }
    return real(sockfd, addr, addrlen);
}

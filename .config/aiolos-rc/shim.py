#!/usr/bin/env python3
"""aiolos-rc shim: a local, path-splitting TLS terminator on a unix socket.

Claude Code is launched with ANTHROPIC_UNIX_SOCKET pointed here (and
ANTHROPIC_BASE_URL unset), which bypasses Claude's client-side "remote control
is only available via api.anthropic.com" gate. This shim terminates the client
TLS (presenting a local api.anthropic.com cert that Claude trusts via
NODE_EXTRA_CA_CERTS) and routes each request by path:

  * /v1/messages*   -> aiolos, with `x-aiolos-account-id: <X>` added
                       => the session's INFERENCE runs on account X.
  * everything else -> api.anthropic.com, forwarded unchanged
                       => remote-control / sessions / identity register under
                          the caller's own (main) claude.ai login, so the
                          session shows up in the MAIN account's RC list.

Config via env:
  RC_SOCK        unix socket path to listen on
  RC_CERT        cert chain (leaf+CA) PEM for TLS termination
  RC_KEY         private key PEM
  RC_AIOLOS_URL  aiolos base URL, e.g. https://host[:port]  (never logged)
  RC_ACCOUNT_ID  aiolos account id X for the inference leg
  RC_DEBUG       if set, log one line per request (method, path, upstream)

No request/response bodies or tokens are ever logged.
"""
import asyncio
import os
import ssl
import sys
import urllib.parse

SOCK = os.environ.get("RC_SOCK")           # unix-socket mode (legacy)
LISTEN_PORT = os.environ.get("RC_PORT")    # TCP mode on 127.0.0.1 (preload redirect)
CERT = os.environ["RC_CERT"]
KEY = os.environ["RC_KEY"]
AIOLOS_URL = os.environ["RC_AIOLOS_URL"]
# Empty/unset -> no-pin mode: forward inference to aiolos with no account header,
# so aiolos load-balances across all accounts as it normally does.
ACCOUNT_ID = os.environ.get("RC_ACCOUNT_ID") or ""
DEBUG = bool(os.environ.get("RC_DEBUG"))

ANTHROPIC_HOST = "api.anthropic.com"
ANTHROPIC_PORT = 443

_au = urllib.parse.urlparse(AIOLOS_URL)
AIOLOS_HOST = _au.hostname
AIOLOS_TLS = _au.scheme == "https"
AIOLOS_PORT = _au.port or (443 if AIOLOS_TLS else 80)

server_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
server_ctx.load_cert_chain(certfile=CERT, keyfile=KEY)
client_ctx = ssl.create_default_context()

HOP_BY_HOP = {
    "host", "connection", "proxy-connection", "keep-alive",
    "transfer-encoding", "upgrade", "te", "trailer",
    # We re-frame the body (dechunk + buffer) and append our own
    # Content-Length below, so the shim must own it exclusively. Forwarding
    # the client's Content-Length too would emit a duplicate header, which
    # RFC 9110 forbids and strict upstream parsers reject as smuggling.
    "content-length",
    # never let the client smuggle its own pin
    "x-aiolos-account-id", "x-aiolos-force-account-strict",
}


def log(msg):
    if DEBUG:
        sys.stderr.write(f"[shim] {msg}\n")
        sys.stderr.flush()


def is_inference(path):
    return path.split("?", 1)[0].startswith("/v1/messages")


def is_upgrade(headers):
    # A real protocol upgrade (WebSocket): `Upgrade: <proto>` and/or
    # `Connection: Upgrade`. Only these switch the connection to a raw tunnel.
    for k, v in headers:
        kl = k.lower()
        if kl == "upgrade" and v.strip():
            return True
        if kl == "connection" and "upgrade" in v.lower():
            return True
    return False


async def read_headers(reader):
    head = await reader.readuntil(b"\r\n\r\n")
    lines = head.split(b"\r\n")
    request_line = lines[0].decode("latin1")
    headers = []
    for ln in lines[1:]:
        if not ln:
            continue
        k, _, v = ln.partition(b":")
        headers.append((k.decode("latin1").strip(), v.decode("latin1").strip()))
    return request_line, headers


async def read_body(reader, headers):
    clen = 0
    chunked = False
    expect_continue = False
    for k, v in headers:
        kl = k.lower()
        if kl == "content-length":
            try:
                clen = int(v)
            except ValueError:
                clen = 0
        elif kl == "transfer-encoding" and "chunked" in v.lower():
            chunked = True
        elif kl == "expect" and "100-continue" in v.lower():
            expect_continue = True
    return clen, chunked, expect_continue


async def pump(src, dst):
    try:
        while True:
            b = await src.read(65536)
            if not b:
                break
            dst.write(b)
            await dst.drain()
    except Exception:
        pass


async def tunnel(cr, cw, ur, uw):
    """Full-duplex byte relay between client and upstream. Closing one side's
    writer on EOF tears down the peer half, so WebSocket upgrades, SSE, long-poll,
    keep-alive and bidirectional streams all pass through transparently."""
    async def half(src, dst):
        try:
            while True:
                data = await src.read(65536)
                if not data:
                    break
                dst.write(data)
                await dst.drain()
        except Exception:
            pass
        finally:
            try:
                dst.close()
            except Exception:
                pass
    await asyncio.gather(half(cr, uw), half(ur, cw))


async def handle(cr, cw):
    upstream_w = None
    try:
        request_line, headers = await read_headers(cr)
        parts = request_line.split(" ")
        if len(parts) != 3:
            return
        method, path, ver = parts

        # Route by REQUEST, not by connection. Every buffered response forces
        # `Connection: close`, so the client never pools a shim connection to carry
        # a later request of a different class. Only a real WebSocket upgrade turns
        # the connection into a raw bidirectional tunnel — after `101` it carries no
        # further HTTP requests, so there is nothing to misroute. This keeps
        # inference classified per-request (a pooled control connection can't smuggle
        # a /v1/messages POST straight to Anthropic, off aiolos and off the pin)
        # while still fixing the remote-control bridge upgrade that a header-stripping
        # buffered proxy broke ("Transport recovery exhausted").
        if is_upgrade(headers):
            out = [request_line]
            for k, v in headers:
                # Preserve Upgrade/Connection etc; only drop Host (rewritten) and
                # the aiolos pin guards (never let a client smuggle them upstream).
                if k.lower() in ("host", "x-aiolos-account-id",
                                 "x-aiolos-force-account-strict"):
                    continue
                out.append(f"{k}: {v}")
            out.append(f"Host: {ANTHROPIC_HOST}")
            head = ("\r\n".join(out) + "\r\n\r\n").encode("latin1")

            log(f"{method} {path} -> anthropic (upgrade tunnel)")
            ur, uw = await asyncio.open_connection(
                ANTHROPIC_HOST, ANTHROPIC_PORT,
                ssl=client_ctx, server_hostname=ANTHROPIC_HOST)
            upstream_w = uw
            uw.write(head)          # request head; frames flow via the tunnel
            await uw.drain()
            await tunnel(cr, cw, ur, uw)
            return

        # --- buffered per-request: inference -> aiolos (+pin); else -> Anthropic ---
        clen, chunked, expect_continue = await read_body(cr, headers)
        if expect_continue:
            cw.write(b"HTTP/1.1 100 Continue\r\n\r\n")
            await cw.drain()

        body = b""
        if chunked:
            while True:
                size_line = await cr.readuntil(b"\r\n")
                size = int(size_line.strip().split(b";")[0] or b"0", 16)
                if size == 0:
                    await cr.readuntil(b"\r\n")
                    break
                body += await cr.readexactly(size)
                await cr.readexactly(2)
        elif clen:
            body = await cr.readexactly(clen)

        if is_inference(path):
            host, port, use_tls = AIOLOS_HOST, AIOLOS_PORT, AIOLOS_TLS
            if ACCOUNT_ID:
                extra = [("x-aiolos-account-id", ACCOUNT_ID),
                         ("x-aiolos-force-account-strict", "true")]
                dest = "aiolos[" + ACCOUNT_ID + "]"
            else:
                extra = []            # no pin -> aiolos load-balances
                dest = "aiolos[lb]"
        else:
            host, port, use_tls = ANTHROPIC_HOST, ANTHROPIC_PORT, True
            extra = []
            dest = "anthropic"

        log(f"{method} {path} -> {dest}")

        out = [f"{method} {path} {ver}"]
        for k, v in headers:
            if k.lower() in HOP_BY_HOP or k.lower() == "expect":
                continue
            out.append(f"{k}: {v}")
        hosthdr = host if port in (443, 80) else f"{host}:{port}"
        out.append(f"Host: {hosthdr}")
        for k, v in extra:
            out.append(f"{k}: {v}")
        out.append(f"Content-Length: {len(body)}")
        out.append("Connection: close")
        req_bytes = ("\r\n".join(out) + "\r\n\r\n").encode("latin1") + body

        ur, uw = await asyncio.open_connection(
            host, port,
            ssl=(client_ctx if use_tls else None),
            server_hostname=(host if use_tls else None),
        )
        upstream_w = uw
        uw.write(req_bytes)
        await uw.drain()

        # Relay response until upstream closes (Connection: close). Handles
        # Content-Length, chunked, and SSE streaming uniformly. Peek the first
        # chunk to log the upstream status line under RC_DEBUG (no bodies) —
        # this is what makes a failed remote-control bridge init diagnosable.
        first = await ur.read(65536)
        if first:
            if DEBUG:
                try:
                    status_line = first.split(b"\r\n", 1)[0].decode("latin1", "replace")
                    log(f"    <- {dest}: {status_line}")
                except Exception:
                    pass
            cw.write(first)
            await cw.drain()
        await pump(ur, cw)
    except (asyncio.IncompleteReadError, ConnectionError, asyncio.LimitOverrunError):
        pass
    except Exception as e:
        log(f"error: {type(e).__name__}: {e}")
    finally:
        for w in (upstream_w, cw):
            try:
                if w is not None:
                    w.close()
            except Exception:
                pass


async def main():
    if LISTEN_PORT is not None:
        # int(LISTEN_PORT) may be 0 -> the OS assigns a free ephemeral port; we
        # report the actual bound port to RC_PORTFILE so the launcher can point
        # this session's LD_PRELOAD at it (one shim per session, no fixed port).
        server = await asyncio.start_server(
            handle, "127.0.0.1", int(LISTEN_PORT), ssl=server_ctx)
        actual_port = server.sockets[0].getsockname()[1]
        where = f"127.0.0.1:{actual_port}"
        portfile = os.environ.get("RC_PORTFILE")
        if portfile:
            with open(portfile, "w") as f:
                f.write(str(actual_port))
    else:
        server = await asyncio.start_unix_server(handle, path=SOCK, ssl=server_ctx)
        where = SOCK
    acct = ACCOUNT_ID if ACCOUNT_ID else "(load-balanced)"
    log(f"listening {where}  inference->aiolos({AIOLOS_HOST}:{AIOLOS_PORT}) acct={acct}  rest->{ANTHROPIC_HOST}")
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass

import os
import runpy
import socket
from http.client import HTTPException
from urllib.request import Request, urlopen

import dns.exception
import dns.inet
import dns.message
import dns.query
from dnslib import DNSError, DNSRecord


def send_over_https(record, _dest, _port=53, tcp=False, ipv6=False, timeout=None):
    request = Request(
        "https://dns.google/dns-query",
        data=record.pack(),
        headers={
            "Content-Type": "application/dns-message",
            "Accept": "application/dns-message",
        },
    )
    try:
        with urlopen(request, timeout=timeout or 5) as response:
            content = response.read(65536)
        if len(content) > 65535:
            raise ValueError("Oversized DNS response")
        DNSRecord.parse(content)
        return content
    except (OSError, HTTPException, DNSError, ValueError) as error:
        raise TimeoutError("DNS-over-HTTPS upstream failed") from error


def send_over_tcp(record, dest, port=53, tcp=False, timeout=None, ipv6=False):
    try:
        message = dns.message.from_wire(bytes(record.pack()))
        if not dns.inet.is_address(dest):
            family = socket.AF_INET6 if ipv6 else socket.AF_INET
            dest = socket.getaddrinfo(dest, port, family, socket.SOCK_STREAM)[0][4][0]
        response = dns.query.tcp(message, dest, port=port, timeout=timeout)
        return response.to_wire()
    except (
        dns.exception.DNSException,
        EOFError,
        OSError,
        DNSError,
        ValueError,
    ) as error:
        raise TimeoutError("DNS-over-TCP upstream failed") from error


if __name__ == "__main__":
    if os.environ.get("STATION_DNS_DOH") == "1":
        DNSRecord.send = send_over_https
    else:
        DNSRecord.send = send_over_tcp
    runpy.run_module("dnslib.intercept", run_name="__main__")

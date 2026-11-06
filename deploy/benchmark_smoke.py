"""Bounded authenticated read through local Caddy with hostname/TLS verification."""
import http.client
from http.cookies import SimpleCookie
from html.parser import HTMLParser
import re
import socket
import ssl
from urllib.parse import urlencode

import benchmark_host as host


class Page(HTMLParser):
    def __init__(self, text):
        super().__init__()
        self.ids = set()
        self.csrf = None
        self.feed(text)

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        self.ids.add(attrs.get("id"))
        if tag == "input" and attrs.get("name") == "_csrf_token":
            self.csrf = attrs.get("value")
        if tag == "meta" and attrs.get("name") == "csrf-token":
            self.csrf = attrs.get("content")


def credentials():
    data = host.read_json(host.ROOT / "smoke-private.json")
    host.require(set(data) == {"email", "password", "record_path"}
                 and isinstance(data["email"], str) and len(data["email"]) <= 160
                 and isinstance(data["password"], str) and 12 <= len(data["password"]) <= 128
                 and re.fullmatch(r"/o/[a-z0-9_-]+/processos/[0-9]+/registros/[0-9]+", data["record_path"]),
                 "Invalid private smoke fixture")
    return data


def smoke():
    data = credentials()
    cookie = SimpleCookie()

    def request(path, form=None):
        # Fixed local socket destination, but real TLS hostname/SNI and certificate validation.
        connection = http.client.HTTPSConnection(host.DOMAIN, timeout=15, context=ssl.create_default_context())
        connection._create_connection = lambda address, timeout, source_address: socket.create_connection(
            ("127.0.0.1", 443), timeout, source_address)
        headers = {"Cookie": "; ".join(key + "=" + value.value for key, value in cookie.items())}
        if form is not None:
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        try:
            connection.request("GET" if form is None else "POST", path,
                               None if form is None else urlencode(form), headers)
            response = connection.getresponse()
            body = response.read(2_000_001)
            host.require(len(body) <= 2_000_000, "Smoke response exceeded its bound")
            for key, value in response.getheaders():
                if key.lower() == "set-cookie":
                    cookie.load(value)
            return response.status, response.getheader("Location"), Page(body.decode())
        finally:
            connection.close()

    status, _, page = request("/entrar")
    host.require(status == 200 and "login-form" in page.ids and page.csrf, "Login smoke failed")
    status, location, _ = request("/entrar", {"_csrf_token": page.csrf,
        "login[email]": data["email"], "login[password]": data["password"]})
    host.require(status == 302 and location and location.startswith("/o/"), "Authentication smoke failed")
    status, _, page = request(data["record_path"])
    host.require(status == 200 and "section-form-request" in page.ids and page.csrf,
                 "Authenticated record smoke failed")
    status, location, _ = request("/sair", {"_method": "delete", "_csrf_token": page.csrf})
    host.require(status == 302 and location == "/entrar", "Logout smoke failed")
    status, location, _ = request(data["record_path"])
    host.require(status == 302 and location == "/entrar", "Session removal smoke failed")
    return {"authenticated_record_read": True, "logout": True, "tls_verified": True,
            "transport": "local Caddy HTTPS; fixed loopback socket, public hostname/SNI"}

"""httpx sync/async transports through the source-bound Flutter network host."""
import base64

import httpx


def install(host):
    def send(request, body):
        value = host("http", {"url": str(request.url), "method": request.method,
            "headers": dict(request.headers), "body": base64.b64encode(body).decode()})
        # The host already decompressed the HTTP body.
        headers = {k: v for k, v in value["headers"].items()
            if k.lower() not in ("content-encoding", "content-length")}
        return httpx.Response(value["status"], headers=headers,
            content=base64.b64decode(value["body"]), request=request)

    class Transport(httpx.BaseTransport):
        def handle_request(self, request):
            return send(request, request.read())

    class AsyncTransport(httpx.AsyncBaseTransport):
        async def handle_async_request(self, request):
            response = send(request, await request.aread())
            return response

    client_init = httpx.Client.__init__
    async_init = httpx.AsyncClient.__init__

    def init(self, *args, **kwargs):
        kwargs["transport"] = Transport()
        kwargs["trust_env"] = False
        client_init(self, *args, **kwargs)
        if "user-agent" not in httpx.Headers(kwargs.get("headers")):
            self.headers.pop("User-Agent", None)

    def init_async(self, *args, **kwargs):
        kwargs["transport"] = AsyncTransport()
        kwargs["trust_env"] = False
        async_init(self, *args, **kwargs)
        if "user-agent" not in httpx.Headers(kwargs.get("headers")):
            self.headers.pop("User-Agent", None)

    httpx.Client.__init__ = init
    httpx.AsyncClient.__init__ = init_async

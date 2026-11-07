"""CORS adapter for observing Immersive Translate through mitmproxy.

The browser extension sends its chrome-extension Origin to the local reverse
proxy. Ollama rejects that Origin, so this addon answers the browser preflight
locally, removes the Origin before forwarding, and restores the matching CORS
response header on the way back.
"""

from mitmproxy import http


ALLOWED_ORIGIN = "chrome-extension://bpoadfkcbjbfhfodiogcnhhhpibjhbnh"


def request(flow: http.HTTPFlow) -> None:
    """Handle extension preflights and sanitize forwarded requests."""
    origin = flow.request.headers.get("Origin")
    if origin != ALLOWED_ORIGIN:
        return

    flow.metadata["immersive_translate_cors_origin"] = origin
    if flow.request.method == "OPTIONS":
        requested_headers = flow.request.headers.get(
            "Access-Control-Request-Headers",
            "authorization,content-type",
        )
        flow.response = http.Response.make(
            204,
            b"",
            {
                "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
                "Access-Control-Allow-Methods": "POST, OPTIONS",
                "Access-Control-Allow-Headers": requested_headers,
                "Access-Control-Max-Age": "86400",
                "Vary": "Origin",
            },
        )
        return

    del flow.request.headers["Origin"]


def response(flow: http.HTTPFlow) -> None:
    """Expose the forwarded Ollama response to the allowed extension."""
    origin = flow.metadata.get("immersive_translate_cors_origin")
    if origin == ALLOWED_ORIGIN:
        flow.response.headers["Access-Control-Allow-Origin"] = ALLOWED_ORIGIN
        flow.response.headers["Vary"] = "Origin"

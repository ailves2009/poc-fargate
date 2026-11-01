"""ECS blue/green lifecycle hook (POST_TEST_TRAFFIC_SHIFT).

The new revision already receives test traffic (requests with the test
header). Production still points at the old revision. This hook calls the
service through the public test rule and tells ECS whether to proceed.

Deterministic on purpose: the outcome is a function of HTTP status codes
and latency, so the same deployment always gets the same verdict.
"""

import json
import os
import time
import urllib.error
import urllib.request

URL = os.environ["TARGET_URL"]
HEADER = os.environ.get("TEST_HEADER", "X-Blue-Green")
HEADER_VALUE = os.environ.get("TEST_HEADER_VALUE", "test")
REQUESTS = int(os.environ.get("REQUESTS", "10"))
MAX_LATENCY_MS = int(os.environ.get("MAX_LATENCY_MS", "1000"))


def probe():
    req = urllib.request.Request(URL, headers={HEADER: HEADER_VALUE})
    started = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            status = resp.status
    except urllib.error.HTTPError as err:
        status = err.code
    except Exception as err:  # DNS, TLS, timeout: a failed probe, not a crash
        return {"status": None, "error": type(err).__name__}
    return {"status": status, "latency_ms": int((time.monotonic() - started) * 1000)}


def handler(event, _context):
    results = [probe() for _ in range(REQUESTS)]
    failures = [
        r for r in results
        if r.get("status") != 200 or r.get("latency_ms", 0) > MAX_LATENCY_MS
    ]
    verdict = "FAILED" if failures else "SUCCEEDED"

    # One structured line per run: it is the audit trail of the gate and the
    # input a future AI "second key" would read (see README, Agents).
    print(json.dumps({
        "stage": event.get("lifecycleStage"),
        "executionId": event.get("executionId"),
        "revision": event.get("executionDetails", {}).get("targetServiceRevisionArn"),
        "url": URL,
        "verdict": verdict,
        "failures": failures,
        "results": results,
    }))
    return {"hookStatus": verdict}

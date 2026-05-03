import re

ISO_TIMESTAMP = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})?$")


def _normalize(value, key=None):
    if isinstance(value, dict):
        return {k: _normalize(v, k) for k, v in value.items()}
    if isinstance(value, list):
        normalized = [_normalize(v) for v in value]
        if key == "tags" and all(isinstance(v, str) for v in normalized):
            normalized.sort()
        return normalized
    if isinstance(value, str) and ISO_TIMESTAMP.match(value):
        return "<scrubbed-timestamp>"
    return value


def test_openapi_unchanged(api_client, snapshot):
    spec = _normalize(api_client.get("/openapi.json").json())
    assert spec == snapshot

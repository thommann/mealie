import re
from typing import Any

import pytest

from tests.utils.fixture_schemas import TestUser

UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", re.I)
ISO_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}")
SOURCE_LINE_RE = re.compile(r"\bline \d+\b")

VOLATILE_KEYS = {"created_at", "update_at", "updated_at"}


def _scrub(value: Any) -> Any:
    if isinstance(value, dict):
        return {k: ("<TIMESTAMP>" if k in VOLATILE_KEYS and v else _scrub(v)) for k, v in value.items()}
    if isinstance(value, list):
        return [_scrub(v) for v in value]
    if isinstance(value, str):
        if UUID_RE.match(value):
            return "<UUID>"
        if ISO_RE.match(value):
            return "<TIMESTAMP>"
        return SOURCE_LINE_RE.sub("line <N>", value)
    return value


def _item(list_id: str, note: str) -> dict:
    return {
        "shopping_list_id": list_id,
        "checked": False,
        "position": 0,
        "note": note,
        "quantity": 1,
        "unit_id": None,
        "food_id": None,
        "recipe_id": None,
        "label_id": None,
    }


@pytest.mark.parametrize(
    "case,method,path,payload_fn,expected_status",
    [
        (
            "happy",
            "post",
            "/api/households/shopping/items",
            lambda sl: _item(str(sl.id), "happy-note"),
            201,
        ),
        (
            "alt_bulk",
            "post",
            "/api/households/shopping/items/create-bulk",
            lambda sl: [_item(str(sl.id), "alt-a"), _item(str(sl.id), "alt-b")],
            201,
        ),
        (
            "error_bad_uuid",
            "post",
            "/api/households/shopping/items",
            lambda sl: {**_item(str(sl.id), "bad"), "shopping_list_id": "not-a-uuid"},
            422,
        ),
    ],
)
def test_shopping_list_items_route(
    api_client,
    snapshot,
    unique_user: TestUser,
    shopping_list,
    case,
    method,
    path,
    payload_fn,
    expected_status,
):
    resp = api_client.request(
        method,
        path,
        json=payload_fn(shopping_list),
        headers=unique_user.token,
    )
    assert resp.status_code == expected_status
    assert _scrub(resp.json()) == snapshot

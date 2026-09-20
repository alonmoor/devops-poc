import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import respx
import httpx
from fastapi.testclient import TestClient
from src.main import app, CATALOG_API_URL

client = TestClient(app)


@respx.mock
def test_create_order_success():
    respx.get(f"{CATALOG_API_URL}/catalog/sku-1001").mock(
        return_value=httpx.Response(200, json={"name": "Wireless Mouse", "price": 19.99, "stock": 120})
    )
    resp = client.post("/orders", json={"sku": "sku-1001", "quantity": 2})
    assert resp.status_code == 200
    body = resp.json()
    assert body["total"] == 39.98
    assert "order_id" in body


@respx.mock
def test_create_order_sku_not_found():
    respx.get(f"{CATALOG_API_URL}/catalog/does-not-exist").mock(return_value=httpx.Response(404))
    resp = client.post("/orders", json={"sku": "does-not-exist", "quantity": 1})
    assert resp.status_code == 404


@respx.mock
def test_create_order_insufficient_stock():
    respx.get(f"{CATALOG_API_URL}/catalog/sku-1003").mock(
        return_value=httpx.Response(200, json={"name": "USB-C Hub", "price": 34.50, "stock": 0})
    )
    resp = client.post("/orders", json={"sku": "sku-1003", "quantity": 1})
    assert resp.status_code == 409


@respx.mock
def test_create_order_catalog_unreachable():
    respx.get(f"{CATALOG_API_URL}/catalog/sku-1001").mock(side_effect=httpx.ConnectError("connection refused"))
    resp = client.post("/orders", json={"sku": "sku-1001", "quantity": 1})
    assert resp.status_code == 502


def test_get_unknown_order_returns_404():
    resp = client.get("/orders/does-not-exist-id")
    assert resp.status_code == 404

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from fastapi.testclient import TestClient
from src.main import app

client = TestClient(app)


def test_healthz():
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


def test_readyz():
    resp = client.get("/readyz")
    assert resp.status_code == 200


def test_get_known_product():
    resp = client.get("/catalog/sku-1001")
    assert resp.status_code == 200
    body = resp.json()
    assert body["name"] == "Wireless Mouse"
    assert body["stock"] == 120


def test_get_unknown_product_returns_404():
    resp = client.get("/catalog/does-not-exist")
    assert resp.status_code == 404


def test_list_products_returns_all_skus():
    resp = client.get("/catalog")
    assert resp.status_code == 200
    skus = {item["sku"] for item in resp.json()}
    assert skus == {"sku-1001", "sku-1002", "sku-1003"}

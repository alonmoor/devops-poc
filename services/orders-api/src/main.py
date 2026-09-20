"""
orders-api
----------
Customer-facing microservice. This is the ONE service exposed externally
(via Ingress/LoadBalancer + TLS). It talks to catalog-api internally over
its ClusterIP Service DNS name - that traffic never leaves the cluster
network, so it doesn't need TLS termination or external auth, only a
NetworkPolicy allowing the call.
"""
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import httpx
import os
import uuid

app = FastAPI(title="orders-api")

# Internal Kubernetes DNS name of the catalog-api Service - this is the
# whole point of ClusterIP: stable internal name, no external exposure.
# e.g. "http://catalog-api.catalog.svc.cluster.local:8080"
CATALOG_API_URL = os.getenv("CATALOG_API_URL", "http://catalog-api:8080")

ORDERS = {}


class OrderRequest(BaseModel):
    sku: str
    quantity: int


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/readyz")
def readyz():
    return {"status": "ready"}


@app.post("/orders")
def create_order(req: OrderRequest):
    # Internal service-to-service call over ClusterIP.
    with httpx.Client(timeout=3.0) as client:
        try:
            resp = client.get(f"{CATALOG_API_URL}/catalog/{req.sku}")
        except httpx.RequestError as exc:
            # Fails closed with a clear 502 rather than hanging - important
            # for readiness/liveness semantics under a NetworkPolicy
            # misconfiguration during rollout.
            raise HTTPException(status_code=502, detail=f"catalog-api unreachable: {exc}")

    if resp.status_code == 404:
        raise HTTPException(status_code=404, detail="SKU not found in catalog")

    product = resp.json()
    if product["stock"] < req.quantity:
        raise HTTPException(status_code=409, detail="Insufficient stock")

    order_id = str(uuid.uuid4())
    ORDERS[order_id] = {
        "sku": req.sku,
        "quantity": req.quantity,
        "unit_price": product["price"],
        "total": round(product["price"] * req.quantity, 2),
    }
    return {"order_id": order_id, **ORDERS[order_id]}


@app.get("/orders/{order_id}")
def get_order(order_id: str):
    order = ORDERS.get(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    return {"order_id": order_id, **order}


@app.get("/version")
def version():
    return {"version": os.getenv("IMAGE_TAG", "dev-local")}

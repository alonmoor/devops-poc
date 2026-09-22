"""
catalog-api
-----------
Minimal internal-facing microservice. Exposes a small in-memory product
catalog. Consumed internally by orders-api over ClusterIP - never exposed
directly to the internet.
"""
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import os

app = FastAPI(title="catalog-api")

# In-memory "DB" - a real implementation would use a managed datastore.
# Kept intentionally simple: this is a POC for the CI/CD + platform pattern,
# not a production catalog service.
CATALOG = {
    "sku-1001": {"name": "Wireless Mouse", "price": 19.99, "stock": 120},
    "sku-1002": {"name": "Mechanical Keyboard", "price": 79.99, "stock": 45},
    "sku-1003": {"name": "USB-C Hub", "price": 34.50, "stock": 0},
}


class Product(BaseModel):
    sku: str
    name: str
    price: float
    stock: int


@app.get("/healthz")
def healthz():
    """Liveness probe target - process is up."""
    return {"status": "ok"}


@app.get("/readyz")
def readyz():
    """Readiness probe target - service can serve traffic.
    In a real service this would check DB connectivity etc."""
    return {"status": "ready"}


@app.get("/catalog/{sku}", response_model=Product)
def get_product(sku: str):
    item = CATALOG.get(sku)
    if not item:
        raise HTTPException(status_code=404, detail="SKU not found")
    return Product(sku=sku, **item)


@app.get("/catalog")
def list_products():
    return [{"sku": sku, **data} for sku, data in CATALOG.items()]


@app.get("/version")
def version():
    # Populated at build time via IMAGE_TAG env var - lets us verify
    # which immutable image tag is actually running in a given environment.
    return {"version": os.getenv("IMAGE_TAG", "dev-local")}
# CI test comment - triggers build-and-deploy workflow
# trigger full pipeline test

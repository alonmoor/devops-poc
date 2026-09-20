# --- Build stage: install deps into a throwaway layer ---
FROM python:3.12-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --target=/build/deps -r requirements.txt

# --- Runtime stage: copy only what's needed, run as non-root ---
FROM python:3.12-slim
WORKDIR /app

# Non-root user - reduces blast radius if the container is compromised,
# and is required by most Pod Security Admission "restricted" profiles.
RUN useradd --uid 10001 --no-create-home appuser
COPY --from=builder /build/deps /usr/local/lib/python3.12/site-packages
COPY src/ ./src/

ARG IMAGE_TAG=dev-local
ENV IMAGE_TAG=${IMAGE_TAG}

USER 10001
EXPOSE 8080
CMD ["python", "-m", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8080"]

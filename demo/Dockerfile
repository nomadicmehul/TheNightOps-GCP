# Demo Application Container
# A simple FastAPI app that simulates various failure modes.
#
# Uses Docker Hardened Image base for consistency with production.
# Run `docker scout cves nightops-demo-api:latest` to scan.

FROM docker.io/library/python:3.11-slim

LABEL org.opencontainers.image.title="NightOps Demo API"
LABEL org.opencontainers.image.description="Demo application for TheNightOps incident simulation"
LABEL com.docker.scout.policy="hardened"

WORKDIR /app

RUN pip install --no-cache-dir fastapi uvicorn psutil

COPY scenarios/demo_app.py .

# Run as non-root
RUN groupadd -r demo && useradd -r -g demo -d /app -s /sbin/nologin demo \
    && chown -R demo:demo /app
USER demo

EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/healthz')" || exit 1

CMD ["uvicorn", "demo_app:app", "--host", "0.0.0.0", "--port", "8080"]

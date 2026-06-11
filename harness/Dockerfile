# Toolbox image for ingest / evaluate / report. Kept deliberately small —
# the heavy lifting (inference, vector DB) happens in the other services.
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# Source is bind-mounted at runtime (see docker-compose.yml), so nothing else
# needs to be copied in. CMD is overridden per invocation.
CMD ["python", "--help"]

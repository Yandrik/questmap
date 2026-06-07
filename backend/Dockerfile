FROM ghcr.io/astral-sh/uv:python3.13-bookworm-slim

WORKDIR /app

ENV PYTHONUNBUFFERED=1
ENV LOG_LEVEL=INFO

COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

COPY *.py ./
COPY migrations ./migrations

EXPOSE 8000

CMD ["uv", "run", "--frozen", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--log-level", "info", "--access-log"]

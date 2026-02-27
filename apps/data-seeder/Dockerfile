FROM python:3.11-slim

WORKDIR /app

COPY apps/data-seeder /app/data-seeder

RUN pip install --no-cache-dir /app/data-seeder

WORKDIR /app/data-seeder

CMD ["python", "-u", "-m", "src.generator"]

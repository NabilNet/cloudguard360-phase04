# CloudGuard360 Phase 04: reuse Microsoft Azure Voting App source (NOT a new app).
# Bootstrap snapshots Azure-Samples/azure-voting-app-redis/azure-vote into vendor/azure-vote/.
# Modern base prevents dependence on the retired mcr.microsoft.com/azuredocs/azure-vote-front:v1.
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
RUN pip install --no-cache-dir "Flask>=3.1,<4" "redis>=5,<7" "gunicorn>=23,<24"
COPY vendor/azure-vote/ /app/
EXPOSE 80
CMD ["gunicorn", "--bind", "0.0.0.0:80", "--workers", "2", "main:app"]

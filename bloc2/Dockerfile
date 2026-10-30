# Image unique du pipeline : chaque service compose lance un script différent.
#   docker build -t bloc2-pipeline .
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Dépendances d'abord : cette couche reste en cache tant que le fichier ne change pas
COPY requirements-pipeline.txt .
RUN pip install --no-cache-dir -r requirements-pipeline.txt

COPY config.py create_db.py etl.py ingestion.py train.py ./

# Utilisateur non root ; data/ et models/ seront des volumes
RUN useradd --create-home appuser \
    && mkdir -p data/processed models \
    && chown -R appuser:appuser /app
USER appuser

# Commande par défaut, remplacée par chaque service du compose
CMD ["python", "etl.py"]

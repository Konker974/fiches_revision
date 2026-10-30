#!/usr/bin/env bash
# =============================================================================
# BLOC 3 — DOCKER : Dockerfile, volumes, docker compose, DockerHub
# =============================================================================
# Sujet : point 8
# Prérequis : Docker installé, projet TechShop (06_fastapi_pydantic.sh → create_app)
# Usage : ./05_docker.sh <fonction>
# =============================================================================

set -euo pipefail

DOCKERHUB_USER="${DOCKERHUB_USER:-moncompte}"
IMAGE="${DOCKERHUB_USER}/techshop-api"
TAG="${TAG:-v1.0.0}"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1 : INSTALLATION
# ─────────────────────────────────────────────────────────────────────────────

install_docker() {
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker "$USER"        # docker sans sudo (se reconnecter)
    docker --version && docker compose version
    docker run --rm hello-world
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2 : DOCKERFILE
# ─────────────────────────────────────────────────────────────────────────────
#  FROM        image de base            WORKDIR   dossier de travail
#  COPY        copie hôte → image       RUN       commande au BUILD (couche)
#  ENV         variable d'environnement EXPOSE    port documenté
#  CMD         commande au RUN (remplaçable)      ENTRYPOINT  commande fixe
# Astuce cache : copier requirements.txt et installer AVANT de copier le code.

write_dockerfile() {
    cat > Dockerfile <<'EOF'
FROM python:3.11-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    MODEL_PATH=/app/models/model.joblib

# 1) Dépendances (couche mise en cache tant que requirements.txt ne change pas)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 2) Code
COPY app/ ./app/
COPY models/ ./models/
COPY train.py .

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

    cat > .dockerignore <<'EOF'
.venv/
__pycache__/
.git/
.env
*.ipynb
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3 : BUILD / RUN / DEBUG
# ─────────────────────────────────────────────────────────────────────────────

build_and_run() {
    docker build -t techshop-api:latest .              # -f autre.Dockerfile si besoin
    docker images
    docker run -d --name api -p 8000:8000 -e LOG_LEVEL=debug techshop-api:latest
    #            ^ détaché    ^ hôte:conteneur
    docker ps                                          # -a : y compris arrêtés
    docker logs -f api
    docker exec -it api bash                           # shell dans le conteneur
    docker inspect api
    docker stop api && docker rm api                   # ou : docker rm -f api
    docker image prune -f && docker system df          # nettoyage / espace
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4 : VOLUMES (persistance des données)
# ─────────────────────────────────────────────────────────────────────────────
# Le système de fichiers d'un conteneur disparaît avec lui (docker rm).
#  - Volume nommé : géré par Docker (/var/lib/docker/volumes) → BDD, données
#  - Bind mount   : dossier de l'hôte monté tel quel         → code, modèles, config
#  - :ro          : lecture seule

volumes_examples() {
    docker volume create techshop-data
    docker volume ls
    docker volume inspect techshop-data

    # Volume nommé pour la BDD
    docker run -d --name db -e MYSQL_ROOT_PASSWORD=root \
        -v techshop-data:/var/lib/mysql mysql:8.0

    # Bind mount : modèle de l'hôte monté dans le conteneur (pas besoin de rebuild)
    docker run -d --name api -p 8000:8000 \
        -v "$(pwd)/models:/app/models:ro" techshop-api:latest

    docker rm -f db api
    docker volume rm techshop-data                     # les données survivent au rm du conteneur
    docker volume prune -f                             # volumes orphelins
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 5 : DOCKER COMPOSE + depends_on
# ─────────────────────────────────────────────────────────────────────────────
# depends_on (forme courte)  : ordre de DÉMARRAGE uniquement (pas « prêt »)
# depends_on (forme longue)  : condition
#    service_started               → démarré (= forme courte)
#    service_healthy               → healthcheck OK (BDD vraiment prête)
#    service_completed_successfully → job terminé avec code 0 (ex : migration, train)

write_compose() {
    cat > docker-compose.yml <<'EOF'
services:
  db:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: root
      MYSQL_DATABASE: techshop
    volumes:
      - db-data:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-proot"]
      interval: 5s
      timeout: 3s
      retries: 10

  train:                                  # job ponctuel : entraîne et écrit le modèle
    build: .
    command: ["python", "train.py"]
    volumes:
      - ./models:/app/models

  api:
    build: .                              # ou image: moncompte/techshop-api:v1.0.0
    ports:
      - "8000:8000"
    env_file: .env
    environment:
      DB_HOST: db                         # le nom du service sert de nom DNS
    volumes:
      - ./models:/app/models:ro
    depends_on:
      db:
        condition: service_healthy
      train:
        condition: service_completed_successfully
    restart: unless-stopped

  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./config/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    depends_on:
      - api

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    volumes:
      - ./grafana/provisioning/datasources:/etc/grafana/provisioning/datasources:ro
      - grafana-data:/var/lib/grafana
    depends_on:
      - prometheus

volumes:
  db-data:
  grafana-data:
EOF
}

compose_commands() {
    docker compose config                  # valider / afficher le fichier résolu
    docker compose up -d --build           # construire et lancer
    docker compose ps
    docker compose logs -f api
    docker compose exec api bash
    docker compose restart api
    docker compose up -d --scale api=3     # (retirer ports fixes pour scaler)
    docker compose down                    # arrêter + supprimer conteneurs/réseau
    docker compose down -v                 # … et les volumes (perte des données !)
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 6 : DOCKERHUB (dépôts d'un compte)
# ─────────────────────────────────────────────────────────────────────────────
# Nom d'image : <compte>/<dépôt>:<tag>  (tag par défaut : latest)
# Créer un token : hub.docker.com > Account settings > Personal access tokens

dockerhub_push() {
    echo "${DOCKERHUB_TOKEN:?définir DOCKERHUB_TOKEN}" | docker login -u "${DOCKERHUB_USER}" --password-stdin

    docker tag techshop-api:latest "${IMAGE}:${TAG}"
    docker tag techshop-api:latest "${IMAGE}:latest"
    docker push "${IMAGE}:${TAG}"
    docker push "${IMAGE}:latest"          # le dépôt est créé au 1er push (public par défaut)

    docker logout
}

dockerhub_pull() {
    docker pull "${IMAGE}:${TAG}"
    docker run -d -p 8000:8000 "${IMAGE}:${TAG}"
    docker search prometheus               # chercher une image publique
    # Lister les tags d'un dépôt via l'API DockerHub
    curl -s "https://hub.docker.com/v2/repositories/${IMAGE}/tags" | python3 -m json.tool
}

# ─────────────────────────────────────────────────────────────────────────────
# Lancement : ./05_docker.sh <fonction>
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [[ $# -eq 0 ]]; then
        echo "Usage : $0 <fonction>"; declare -F | awk '{print "  - " $3}'
    else
        "$@"
    fi
fi

#!/usr/bin/env bash
# =============================================================================
# BLOC 3 — FASTAPI + PYDANTIC + prometheus-fastapi-instrumentator
# =============================================================================
# Sujet : points 10 (FastAPI / instrumentator) et 11 (pydantic.BaseModel)
# Usage : ./06_fastapi_pydantic.sh <fonction>
# Ordre conseillé : install_deps → create_app → (04_joblib.sh train_and_dump) → run_api
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1 : DÉPENDANCES
# ─────────────────────────────────────────────────────────────────────────────

install_deps() {
    cat > requirements.txt <<'EOF'
fastapi
uvicorn[standard]
pydantic>=2
scikit-learn
joblib
numpy
prometheus-fastapi-instrumentator
prometheus-client
pytest
httpx
EOF
    pip install -r requirements.txt
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2 : SCHÉMAS PYDANTIC (app/schemas.py)
# ─────────────────────────────────────────────────────────────────────────────
# BaseModel : validation + conversion de types + sérialisation JSON automatiques.
# Données invalides dans une requête → FastAPI renvoie 422 avec le détail.

create_schemas() {
    mkdir -p app && touch app/__init__.py
    cat > app/schemas.py <<'EOF'
from typing import Literal, Optional
from pydantic import BaseModel, Field, field_validator


class ClientFeatures(BaseModel):
    """Entrée de /predict."""
    age: int = Field(..., ge=18, le=120, description="Âge du client")
    anciennete_mois: int = Field(..., ge=0)
    nb_commandes: int = Field(..., ge=0)
    panier_moyen: float = Field(..., gt=0)
    nb_reclamations: int = Field(0, ge=0)          # valeur par défaut → optionnel
    segment: Optional[str] = None                  # peut être absent / null

    @field_validator("panier_moyen")
    @classmethod
    def arrondir(cls, v: float) -> float:
        return round(v, 2)

    model_config = {
        "json_schema_extra": {"examples": [{
            "age": 35, "anciennete_mois": 24, "nb_commandes": 12,
            "panier_moyen": 58.5, "nb_reclamations": 1}]}
    }

    def to_list(self) -> list:
        return [self.age, self.anciennete_mois, self.nb_commandes,
                self.panier_moyen, self.nb_reclamations]


class PredictionResponse(BaseModel):
    """Sortie de /predict."""
    churn: int
    probabilite: float = Field(..., ge=0, le=1)
    risque: Literal["faible", "moyen", "eleve"]
    model_version: str
EOF

    # Manipuler un BaseModel en Python
    python3 - <<'EOF'
import sys; sys.path.insert(0, ".")
from pydantic import ValidationError
from app.schemas import ClientFeatures

c = ClientFeatures(age="35", anciennete_mois=24, nb_commandes=12, panier_moyen=58.456)
print(c.age, type(c.age))                 # "35" converti en int
print(c.model_dump())                     # → dict      (v1 : .dict())
print(c.model_dump_json())                # → str JSON  (v1 : .json())
print(ClientFeatures.model_validate({"age": 40, "anciennete_mois": 1,
      "nb_commandes": 0, "panier_moyen": 10}))     # (v1 : parse_obj)
try:
    ClientFeatures(age=10, anciennete_mois=-1, nb_commandes=0, panier_moyen=0)
except ValidationError as e:
    print(e.error_count(), "erreurs :", [err["loc"] for err in e.errors()])
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3 : APPLICATION FASTAPI INSTRUMENTÉE (app/main.py)
# ─────────────────────────────────────────────────────────────────────────────
# Instrumentator().instrument(app).expose(app) :
#   - ajoute un middleware qui mesure chaque requête
#   - expose GET /metrics au format texte Prometheus
#   Métriques par défaut : http_requests_total, http_request_duration_seconds,
#   http_request_size_bytes, http_response_size_bytes

create_app() {
    create_schemas
    cat > app/main.py <<'EOF'
import os
from contextlib import asynccontextmanager

import joblib
from fastapi import FastAPI, HTTPException
from prometheus_client import Counter
from prometheus_fastapi_instrumentator import Instrumentator

from app.schemas import ClientFeatures, PredictionResponse

MODEL_PATH = os.getenv("MODEL_PATH", "models/model.joblib")
MODEL_VERSION = os.getenv("MODEL_VERSION", "1.0.0")
ml = {}

# Métrique métier personnalisée (apparaîtra aussi sur /metrics)
PREDICTIONS = Counter("techshop_predictions_total", "Prédictions par classe", ["churn"])


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Chargement du modèle une seule fois au démarrage
    if os.path.exists(MODEL_PATH):
        ml["model"] = joblib.load(MODEL_PATH)
    yield
    ml.clear()


app = FastAPI(title="TechShop Churn API", version=MODEL_VERSION, lifespan=lifespan)

Instrumentator(
    excluded_handlers=["/metrics"],       # ne pas mesurer le scraping lui-même
).instrument(app).expose(app, endpoint="/metrics", include_in_schema=False)


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/ready")
def ready():
    if "model" not in ml:
        raise HTTPException(status_code=503, detail="Modèle non chargé")
    return {"status": "ready", "model_version": MODEL_VERSION}


@app.post("/predict", response_model=PredictionResponse)
def predict(client: ClientFeatures):
    if "model" not in ml:
        raise HTTPException(status_code=503, detail="Modèle non chargé")
    proba = float(ml["model"].predict_proba([client.to_list()])[0][1])
    churn = int(proba >= 0.5)
    PREDICTIONS.labels(churn=str(churn)).inc()
    risque = "eleve" if proba >= 0.7 else "moyen" if proba >= 0.3 else "faible"
    return PredictionResponse(churn=churn, probabilite=round(proba, 4),
                              risque=risque, model_version=MODEL_VERSION)


@app.get("/items/{item_id}")
def get_item(item_id: int, q: str | None = None):
    # paramètre de chemin (typé) + paramètre de requête optionnel ?q=
    return {"item_id": item_id, "q": q}
EOF
    echo "app/ créée : schemas.py + main.py"
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4 : LANCER ET TESTER
# ─────────────────────────────────────────────────────────────────────────────

run_api() {
    uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
    # --reload : redémarre à chaque modif (dev)  |  --workers 4 : prod
    # Swagger UI : http://localhost:8000/docs   ReDoc : /redoc   Schéma : /openapi.json
}

smoke_test() {
    curl -s localhost:8000/health
    curl -s localhost:8000/ready
    curl -s -X POST localhost:8000/predict -H "Content-Type: application/json" \
         -d '{"age": 52, "anciennete_mois": 3, "nb_commandes": 1, "panier_moyen": 20, "nb_reclamations": 4}'
    curl -s localhost:8000/metrics | grep -E '^(http_requests_total|techshop_predictions_total)'
}

# ─────────────────────────────────────────────────────────────────────────────
# Lancement : ./06_fastapi_pydantic.sh <fonction>
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [[ $# -eq 0 ]]; then
        echo "Usage : $0 <fonction>"; declare -F | awk '{print "  - " $3}'
    else
        "$@"
    fi
fi

#!/usr/bin/env bash
# =============================================================================
# BLOC 3 — PYTEST (tests unitaires + tests de l'API FastAPI)
# =============================================================================
# Sujet : point 9
# Prérequis : app/ créée par 06_fastapi_pydantic.sh, modèle par 04_joblib.sh
# Usage : ./07_pytest.sh <fonction>
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1 : RAPPELS
# ─────────────────────────────────────────────────────────────────────────────
# - Fichiers test_*.py ou *_test.py, fonctions test_*, classes Test*
# - assert simple (pytest réécrit l'assert pour afficher le détail)
# - pytest.raises(Exc)            → vérifier une exception
# - @pytest.fixture               → préparer des données / ressources (yield = teardown)
# - conftest.py                   → fixtures partagées, découvertes automatiquement
# - @pytest.mark.parametrize      → même test, plusieurs jeux de données
# - monkeypatch                   → remplacer env / attributs le temps d'un test

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2 : ÉCRIRE LES TESTS
# ─────────────────────────────────────────────────────────────────────────────

write_tests() {
    mkdir -p tests && touch tests/__init__.py

    cat > pytest.ini <<'EOF'
[pytest]
testpaths = tests
pythonpath = .
markers =
    slow: tests lents (désélection : -m "not slow")
EOF

    cat > tests/conftest.py <<'EOF'
import pytest
from fastapi.testclient import TestClient

from app.main import app


@pytest.fixture(scope="module")
def client():
    # Le "with" déclenche le lifespan → le modèle est chargé
    with TestClient(app) as c:
        yield c


@pytest.fixture
def client_valide():
    return {"age": 35, "anciennete_mois": 24, "nb_commandes": 12,
            "panier_moyen": 58.5, "nb_reclamations": 1}
EOF

    cat > tests/test_schemas.py <<'EOF'
import pytest
from pydantic import ValidationError

from app.schemas import ClientFeatures


def test_conversion_types(client_valide):
    c = ClientFeatures(**{**client_valide, "age": "40"})
    assert c.age == 40


@pytest.mark.parametrize("champ, valeur", [
    ("age", 10),               # < 18
    ("anciennete_mois", -1),
    ("panier_moyen", 0),
])
def test_valeurs_invalides(client_valide, champ, valeur):
    with pytest.raises(ValidationError):
        ClientFeatures(**{**client_valide, champ: valeur})
EOF

    cat > tests/test_api.py <<'EOF'
import pytest


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


def test_predict_ok(client, client_valide):
    r = client.post("/predict", json=client_valide)
    assert r.status_code == 200
    body = r.json()
    assert body["churn"] in (0, 1)
    assert 0 <= body["probabilite"] <= 1
    assert body["risque"] in ("faible", "moyen", "eleve")


@pytest.mark.parametrize("payload", [
    {},                                   # champs manquants
    {"age": "abc"},                       # mauvais type
])
def test_predict_422(client, payload):
    assert client.post("/predict", json=payload).status_code == 422


def test_metrics_exposees(client):
    client.get("/health")
    r = client.get("/metrics")
    assert r.status_code == 200
    assert "http_requests_total" in r.text


def test_version_via_env(monkeypatch):
    monkeypatch.setenv("MODEL_VERSION", "9.9.9")
    import os
    assert os.getenv("MODEL_VERSION") == "9.9.9"
EOF
    echo "tests/ créés"
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3 : LANCER PYTEST
# ─────────────────────────────────────────────────────────────────────────────

run_tests() {
    pytest                                 # tous les tests
    pytest -v                              # verbeux (un test par ligne)
    pytest tests/test_api.py               # un fichier
    pytest tests/test_api.py::test_health  # un test précis
    pytest -k "predict and not 422"        # filtre par nom
    pytest -m "not slow"                   # filtre par marker
    pytest -x                              # stop au 1er échec
    pytest --lf                            # relancer uniquement les derniers échecs
    pytest -s                              # afficher les print()
    pytest --fixtures                      # fixtures disponibles
}

coverage_and_ci() {
    pip install pytest-cov
    pytest --cov=app --cov-report=term-missing
    pytest --junitxml=report.xml           # rapport lu par GitLab (artifacts:reports:junit)
    # Code retour : 0 = OK, 1 = échecs → le job CI échoue automatiquement
}

# ─────────────────────────────────────────────────────────────────────────────
# Lancement : ./07_pytest.sh <fonction>
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [[ $# -eq 0 ]]; then
        echo "Usage : $0 <fonction>"; declare -F | awk '{print "  - " $3}'
    else
        "$@"
    fi
fi

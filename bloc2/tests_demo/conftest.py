import sys
from pathlib import Path

import pytest

# Rend importables les scripts du bloc 2 (etl.py, ingestion.py...) pour la partie 7
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


@pytest.fixture
def commande_simple():
    """Disponible dans TOUS les fichiers de test du dossier, sans import."""
    return {"id": 42, "lignes": [{"prix": 10.0, "qte": 2}, {"prix": 5.0, "qte": 1}]}


@pytest.fixture
def grosse_commande():
    return {"id": 99, "lignes": [{"prix": 600.0, "qte": 2}]}

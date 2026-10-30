import json

import pytest

from boutique import charger_commandes


@pytest.fixture
def fichier_commandes(tmp_path):
    """Une fixture peut utiliser une autre fixture (ici tmp_path)."""
    chemin = tmp_path / "commandes.json"
    chemin.write_text(json.dumps([{"id": 1}, {"id": 2}]), encoding="utf-8")
    print(f"\n[setup] fichier créé : {chemin.name}")
    yield chemin                      # <- valeur injectée dans le test
    print("[teardown] nettoyage après le test")


def test_charger_commandes(fichier_commandes):
    commandes = charger_commandes(fichier_commandes)
    assert [c["id"] for c in commandes] == [1, 2]


def test_fichier_absent(tmp_path):
    with pytest.raises(FileNotFoundError):
        charger_commandes(tmp_path / "inexistant.json")


def test_fixture_du_conftest(commande_simple):
    # commande_simple vient de conftest.py, aucun import nécessaire
    assert len(commande_simple["lignes"]) == 2

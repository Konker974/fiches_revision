import io
import json

import pytest

import boutique


# --- Variables d'environnement ---------------------------------------------
def test_database_url_definie(monkeypatch):
    monkeypatch.setenv("DATABASE_URL", "sqlite:///test.db")
    assert boutique.get_database_url() == "sqlite:///test.db"


def test_database_url_absente(monkeypatch):
    # raising=False : pas d'erreur si la variable n'existait pas déjà
    monkeypatch.delenv("DATABASE_URL", raising=False)
    with pytest.raises(RuntimeError, match="non définie"):
        boutique.get_database_url()


# --- Remplacer une fonction (éviter l'appel réseau) ------------------------
def test_convertir_sans_reseau(monkeypatch):
    # convertir() appelle get_taux_change() -> on la remplace par un stub
    monkeypatch.setattr(boutique, "get_taux_change", lambda devise: 1.10)
    assert boutique.convertir(100, "USD") == 110.0


def test_stub_qui_verifie_ses_arguments(monkeypatch):
    appels = []                                  # on note les appels à la main

    def faux_taux(devise):
        appels.append(devise)
        return {"USD": 1.10, "GBP": 0.85}[devise]

    monkeypatch.setattr(boutique, "get_taux_change", faux_taux)
    assert boutique.convertir(100, "GBP") == 85.0
    assert appels == ["GBP"]
    # (c'est fastidieux : unittest.mock fait ce travail d'espion pour nous, cf. partie 6)


# --- Remplacer une dépendance plus bas niveau (urlopen) --------------------
def test_get_taux_change_avec_fausse_reponse_http(monkeypatch):
    def faux_urlopen(url, timeout):
        assert url.endswith("/USD")
        return io.BytesIO(json.dumps({"taux": 1.08}).encode())  # objet "fichier" avec with

    # boutique a fait "from urllib.request import urlopen" :
    # le nom à remplacer est donc boutique.urlopen (voir la règle « où patcher » en partie 6)
    monkeypatch.setattr("boutique.urlopen", faux_urlopen)
    assert boutique.get_taux_change("USD") == 1.08


# --- Piège : les valeurs par défaut sont figées à la définition ------------
def test_piege_valeur_par_defaut(monkeypatch):
    monkeypatch.setattr(boutique, "TVA", 0.055)
    # prix_ttc(prix_ht, taux=TVA) : la valeur par défaut a été calculée À L'IMPORT (0.20)
    assert boutique.prix_ttc(100) == 120.0       # et non 105.5 !


def test_restauration_automatique():
    # Le test précédent a modifié boutique.TVA : monkeypatch l'a remis en place
    assert boutique.TVA == 0.20

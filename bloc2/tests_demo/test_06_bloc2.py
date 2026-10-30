import json

import pytest
from sqlalchemy import func, select
from sqlalchemy.orm import Session

import etl
import ingestion
from create_db import Order, OrderItem, Product, create_database


def ligne(order_id=1, produit="Smart watch ", qte=1, prix=100.0, statut="COMPLETE", **extra):
    """Fabrique une ligne au format du JSON brut."""
    rec = {
        "sales": qte * prix, "type": "TRANSFER", "market": "Europe",
        "date order": "2017-01-10T10:00:00", "date shipping": "2017-01-12T10:00:00",
        "id": order_id, "status": statut, "quantity": qte,
        "loc": {"country": "France", "state": "IDF", "region": "Western Europe", "city": "Paris"},
        "product": {"name": produit, "category_id": 1, "category_name": "Electronics", "price": prix},
        "customer": {"id": 7, "firstname": "Ada", "lastname": "Lovelace",
                     "loc": {"country": "EE. UU.", "state": "PR", "city": "Caguas",
                             "zipcode": 725.0, "street": "1 rue X"}},
    }
    rec.update(extra)
    return rec


@pytest.fixture
def records():
    return [
        ligne(order_id=1, produit="Smart watch "),
        ligne(order_id=1, produit="Smart watch "),               # doublon strict
        ligne(order_id=1, produit="Tente", qte=2, prix=50.0),
        ligne(order_id=2, statut="SUSPECTED_FRAUD"),
    ]


# --- ETL -------------------------------------------------------------------
def test_transform_nettoie(records):
    df = etl.transform(records)
    assert len(df) == 3                                   # doublon supprimé
    assert set(df["product_name"]) == {"Smart watch", "Tente"}   # espaces retirés
    assert df["customer_zipcode"].iloc[0] == "00725"      # float -> texte 5 chiffres
    assert df.loc[df["order_id"] == 2, "is_fraud"].item() == 1
    assert (df["shipping_days"] == 2).all()


def test_validate_rejette_montant_incoherent(records):
    records.append(ligne(order_id=3, sales=999.0))        # sales != qte x prix
    df = etl.transform(records)
    assert 3 not in df["order_id"].values


def test_lastname_manquant_impute(records):
    del records[0]["customer"]["lastname"]
    df = etl.transform(records[:1])
    assert df["customer_lastname"].item() == "Inconnu"


def test_extract_fichier_absent(tmp_path):
    with pytest.raises(FileNotFoundError):
        etl.extract(tmp_path / "absent.json")


def test_extract_refuse_un_objet(tmp_path):
    chemin = tmp_path / "objet.json"
    chemin.write_text(json.dumps({"pas": "une liste"}), encoding="utf-8")
    with pytest.raises(ValueError, match="liste"):
        etl.extract(chemin)


# --- Ingestion dans une base temporaire --------------------------------------
@pytest.fixture
def base_temporaire(tmp_path, monkeypatch):
    url = f"sqlite:///{tmp_path / 'test.db'}"
    monkeypatch.setattr(ingestion, "create_database", lambda: create_database(url=url))
    return create_database(url=url)       # engine pour interroger la base dans le test


def compter(engine, modele):
    with Session(engine) as s:
        return s.scalar(select(func.count()).select_from(modele))


def test_ingestion(records, base_temporaire):
    ingestion.ingest(etl.transform(records))
    assert compter(base_temporaire, Order) == 2
    assert compter(base_temporaire, OrderItem) == 3
    assert compter(base_temporaire, Product) == 2


def test_ingestion_idempotente(records, base_temporaire):
    df = etl.transform(records)
    ingestion.ingest(df)
    ingestion.ingest(df)                  # relancer ne doit pas créer de doublons
    assert compter(base_temporaire, OrderItem) == 3

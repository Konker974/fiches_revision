"""Ingestion du CSV propre dans la base relationnelle.

Le CSV plat (une ligne = une ligne de commande) est découpé en entités
(catégories, produits, clients, commandes, lignes), puis inséré par lots
dans une seule transaction : en cas d'erreur, rien n'est écrit (rollback).

Le script est idempotent : il vide les tables avant de recharger, on peut
donc le relancer sans créer de doublons.

Usage :
    python ingestion.py [--input chemin/orders_clean.csv] [--batch-size 10000]
"""
import argparse
from pathlib import Path

import pandas as pd
from sqlalchemy import delete, func, insert, select
from sqlalchemy.orm import Session

from config import CLEAN_CSV_PATH, get_logger
from create_db import Category, Customer, Order, OrderItem, Product, create_database

logger = get_logger("ingestion")


def load_clean_csv(path: Path) -> pd.DataFrame:
    if not path.exists():
        raise FileNotFoundError(f"{path} introuvable : lancer d'abord `python etl.py`")
    df = pd.read_csv(
        path,
        parse_dates=["order_date", "shipping_date"],
        dtype={"customer_zipcode": "string"},
        keep_default_na=False, na_values=[""],
    )
    logger.info("%d lignes lues depuis %s", len(df), path)
    return df


def split_entities(df: pd.DataFrame) -> dict[str, list[dict]]:
    """Passe du format plat au modèle relationnel (une liste de dicts par table)."""
    categories = (
        df[["category_id", "category_name"]].drop_duplicates("category_id")
        .rename(columns={"category_id": "id", "category_name": "name"})
    )

    products = (
        df[["product_name", "product_price", "category_id"]].drop_duplicates("product_name")
        .rename(columns={"product_name": "name", "product_price": "price"})
        .reset_index(drop=True)
    )
    products.insert(0, "id", products.index + 1)  # clé technique attribuée ici
    product_ids = dict(zip(products["name"], products["id"]))

    customers = (
        df.filter(like="customer_").drop_duplicates("customer_id")
        .rename(columns=lambda c: c.removeprefix("customer_"))
    )

    orders = (
        df[["order_id", "customer_id", "order_date", "shipping_date", "payment_type",
            "status", "market", "order_country", "order_state", "order_region", "order_city"]]
        .drop_duplicates("order_id")
        .rename(columns={"order_id": "id", "order_country": "country", "order_state": "state",
                         "order_region": "region", "order_city": "city"})
    )

    items = pd.DataFrame({
        "order_id": df["order_id"],
        "product_id": df["product_name"].map(product_ids),
        "quantity": df["quantity"],
        "unit_price": df["product_price"],
        "sales": df["sales"],
    })

    def records(frame: pd.DataFrame) -> list[dict]:
        # NaN/NaT -> None pour que la base reçoive de vrais NULL
        frame = frame.astype(object).where(frame.notna(), None)
        return frame.to_dict(orient="records")

    return {
        "categories": records(categories),
        "products": records(products),
        "customers": records(customers),
        "orders": records(orders),
        "order_items": records(items),
    }


# Ordre d'insertion imposé par les clés étrangères (parents d'abord)
TABLES = [
    ("categories", Category),
    ("products", Product),
    ("customers", Customer),
    ("orders", Order),
    ("order_items", OrderItem),
]


def ingest(df: pd.DataFrame, batch_size: int = 10_000) -> None:
    engine = create_database()
    entities = split_entities(df)

    with Session(engine) as session, session.begin():  # commit auto, rollback si exception
        for _, model in reversed(TABLES):  # enfants d'abord pour vider
            session.execute(delete(model))

        for name, model in TABLES:
            rows = entities[name]
            for start in range(0, len(rows), batch_size):
                session.execute(insert(model), rows[start:start + batch_size])
            logger.info("%-12s : %d lignes insérées", name, len(rows))

    # Contrôle post-chargement : les volumes en base correspondent à la source
    with Session(engine) as session:
        for name, model in TABLES:
            count = session.scalar(select(func.count()).select_from(model))
            if count != len(entities[name]):
                raise RuntimeError(f"{name} : {count} en base vs {len(entities[name])} attendues")
    logger.info("Ingestion terminée et vérifiée")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--input", type=Path, default=CLEAN_CSV_PATH)
    parser.add_argument("--batch-size", type=int, default=10_000)
    args = parser.parse_args()
    ingest(load_clean_csv(args.input), args.batch_size)

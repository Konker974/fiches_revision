"""Extraction et transformation des commandes (orders.json -> CSV propre).

Reprend les décisions prises dans le notebook `01_exploration.ipynb` :
    1. Extract   : lecture du JSON brut (liste de lignes de commande imbriquées).
    2. Transform : aplatissement, renommage, typage, nettoyage, contrôles qualité.
    3. Load      : écriture d'un CSV plat, consommé ensuite par `ingestion.py`.

Usage :
    python etl.py [--input chemin/orders.json] [--output chemin/orders_clean.csv]
"""
import argparse
import json
from pathlib import Path

import pandas as pd

from config import CLEAN_CSV_PATH, RAW_DATA_PATH, get_logger

logger = get_logger("etl")

# Colonnes JSON aplaties -> noms snake_case utilisés partout ensuite
COLUMNS = {
    "id": "order_id",
    "date order": "order_date",
    "date shipping": "shipping_date",
    "type": "payment_type",
    "status": "status",
    "market": "market",
    "loc.country": "order_country",
    "loc.state": "order_state",
    "loc.region": "order_region",
    "loc.city": "order_city",
    "sales": "sales",
    "quantity": "quantity",
    "product.name": "product_name",
    "product.price": "product_price",
    "product.category_id": "category_id",
    "product.category_name": "category_name",
    "customer.id": "customer_id",
    "customer.firstname": "customer_firstname",
    "customer.lastname": "customer_lastname",
    "customer.loc.country": "customer_country",
    "customer.loc.state": "customer_state",
    "customer.loc.city": "customer_city",
    "customer.loc.zipcode": "customer_zipcode",
    "customer.loc.street": "customer_street",
}

OPTIONAL_COLUMNS = ["customer.lastname", "customer.loc.zipcode"]

TEXT_COLUMNS = [c for c in COLUMNS.values() if c not in {
    "order_id", "order_date", "shipping_date", "sales", "quantity",
    "product_price", "category_id", "customer_id", "customer_zipcode",
}]


# --------------------------------------------------------------------------- #
# Extract
# --------------------------------------------------------------------------- #
def extract(path: Path) -> list[dict]:
    """Charge le fichier JSON brut. Lève une erreur explicite si absent/invalide."""
    if not path.exists():
        raise FileNotFoundError(f"Fichier source introuvable : {path}")
    logger.info("Lecture de %s (%.0f Mo)", path, path.stat().st_size / 1e6)
    with path.open(encoding="utf-8") as f:
        records = json.load(f)
    if not isinstance(records, list):
        raise ValueError("Le JSON doit contenir une liste de commandes")
    logger.info("%d lignes de commande extraites", len(records))
    return records


# --------------------------------------------------------------------------- #
# Transform
# --------------------------------------------------------------------------- #
def flatten(records: list[dict]) -> pd.DataFrame:
    """Aplatit les objets imbriqués (loc, product, customer.loc) en colonnes."""
    df = pd.json_normalize(records)
    # "order zipcode" est absent de ~86 % des lignes : colonne écartée
    df = df.drop(columns=["order zipcode"], errors="ignore")
    # Champs facultatifs : si aucune ligne du lot ne les contient, la colonne
    # n'existe pas après json_normalize -> on la crée vide (imputée dans clean())
    for col in OPTIONAL_COLUMNS:
        if col not in df.columns:
            df[col] = None
    missing = set(COLUMNS) - set(df.columns)
    if missing:
        raise ValueError(f"Colonnes attendues absentes du JSON : {sorted(missing)}")
    return df[list(COLUMNS)].rename(columns=COLUMNS)


def clean(df: pd.DataFrame) -> pd.DataFrame:
    """Typage, nettoyage des chaînes, valeurs manquantes et doublons."""
    df = df.copy()

    # Chaînes : espaces parasites ("Smart watch " -> "Smart watch")
    for col in TEXT_COLUMNS:
        df[col] = df[col].astype("string").str.strip()

    # Dates ISO 8601
    df["order_date"] = pd.to_datetime(df["order_date"], errors="coerce")
    df["shipping_date"] = pd.to_datetime(df["shipping_date"], errors="coerce")

    # Valeurs manquantes (très rares, cf. notebook)
    df["customer_lastname"] = df["customer_lastname"].fillna("Inconnu")
    # Code postal stocké en float dans le JSON (725.0) -> texte sur 5 chiffres
    df["customer_zipcode"] = (
        df["customer_zipcode"].astype("Int64").astype("string").str.zfill(5)
    )

    # Doublons stricts : aucune clé de ligne dans la source, on les supprime
    before = len(df)
    df = df.drop_duplicates()
    logger.info("%d doublons stricts supprimés", before - len(df))

    # Les champs obligatoires ne doivent pas être vides
    required = ["order_id", "order_date", "customer_id", "product_name", "sales"]
    invalid = df[required].isna().any(axis=1)
    if invalid.any():
        logger.warning("%d lignes rejetées (champ obligatoire vide)", invalid.sum())
        df = df[~invalid]

    return df


def add_features(df: pd.DataFrame) -> pd.DataFrame:
    """Colonnes dérivées utiles pour l'analyse et le ML."""
    df = df.copy()
    df["shipping_days"] = (df["shipping_date"] - df["order_date"]).dt.days
    df["is_fraud"] = (df["status"] == "SUSPECTED_FRAUD").astype(int)
    return df


def validate(df: pd.DataFrame) -> pd.DataFrame:
    """Règles métier : on écarte (et on trace) les lignes incohérentes."""
    rules = {
        "quantité <= 0": df["quantity"] <= 0,
        "prix <= 0": df["product_price"] <= 0,
        "sales != quantité x prix": (df["sales"] - df["quantity"] * df["product_price"]).abs() > 0.01,
        "expédition avant commande": df["shipping_days"] < 0,
    }
    bad = pd.Series(False, index=df.index)
    for label, mask in rules.items():
        if mask.any():
            logger.warning("Règle violée « %s » : %d lignes", label, mask.sum())
        bad |= mask

    # Une commande = un seul client, une seule date, un seul statut
    per_order = df.groupby("order_id")[["customer_id", "order_date", "status"]].nunique()
    inconsistent = per_order[(per_order > 1).any(axis=1)].index
    if len(inconsistent):
        logger.warning("%d commandes incohérentes écartées", len(inconsistent))
        bad |= df["order_id"].isin(inconsistent)

    return df[~bad]


def transform(records: list[dict]) -> pd.DataFrame:
    df = flatten(records)
    df = clean(df)
    df = add_features(df)
    df = validate(df)
    logger.info(
        "%d lignes propres, %d commandes, %d clients, %d produits",
        len(df), df["order_id"].nunique(), df["customer_id"].nunique(),
        df["product_name"].nunique(),
    )
    return df.reset_index(drop=True)


# --------------------------------------------------------------------------- #
# Load (fichier intermédiaire)
# --------------------------------------------------------------------------- #
def save(df: pd.DataFrame, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(path, index=False)
    logger.info("CSV propre écrit : %s", path)


def run(input_path: Path = RAW_DATA_PATH, output_path: Path = CLEAN_CSV_PATH) -> pd.DataFrame:
    df = transform(extract(input_path))
    save(df, output_path)
    return df


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--input", type=Path, default=RAW_DATA_PATH)
    parser.add_argument("--output", type=Path, default=CLEAN_CSV_PATH)
    args = parser.parse_args()
    run(args.input, args.output)

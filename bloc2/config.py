"""Configuration partagée par tous les scripts du bloc 2.

Les valeurs sensibles ou dépendantes de l'environnement (URL de la base,
chemins) sont lues dans les variables d'environnement, avec un fichier
`.env` optionnel. Voir `.env.example`.
"""
import logging
import os
from pathlib import Path

try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).parent / ".env")
except ImportError:  # python-dotenv est optionnel
    pass

BASE_DIR = Path(__file__).resolve().parent

RAW_DATA_PATH = Path(os.getenv("RAW_DATA_PATH", BASE_DIR.parent / "orders.json"))
PROCESSED_DIR = BASE_DIR / "data" / "processed"
CLEAN_CSV_PATH = PROCESSED_DIR / "orders_clean.csv"
MODELS_DIR = BASE_DIR / "models"

# SQLite par défaut (zéro installation) ; MySQL ou PostgreSQL via docker-compose :
# DATABASE_URL=mysql+pymysql://user:password@localhost:3307/shop
# DATABASE_URL=postgresql+psycopg://user:password@localhost:5433/shop
DATABASE_URL = os.getenv("DATABASE_URL", f"sqlite:///{BASE_DIR / 'data' / 'shop.db'}")


def get_logger(name: str) -> logging.Logger:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)-7s | %(name)s | %(message)s",
        datefmt="%H:%M:%S",
    )
    return logging.getLogger(name)

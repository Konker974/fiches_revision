from create_db import Personnal, create_database
from sqlalchemy import delete, func, insert, select
from sqlalchemy.orm import Session
import pandas as pd
from pathlib import Path



def extract(path: Path) -> pd.DataFrame:
    """Charge le fichier JSON brut. Lève une erreur explicite si absent/invalide."""
    if not path.exists():
        raise FileNotFoundError(f"Fichier source introuvable : {path}")
    with path.open(encoding="utf-8") as f:
        records = pd.read_csv(path)
    if not isinstance(records, pd.Dataframe):
        raise ValueError("Le JSON doit contenir une liste de commandes")
    return records







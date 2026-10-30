"""
Script ETL

Télécharge et transforme le dataset
"""

import argparse
import requests
import pandas as pd
import os
from pathlib import Path
from sqlalchemy import (
    CheckConstraint, DateTime, Float, ForeignKey, Integer, String,
    create_engine,
)
from sqlalchemy.engine import Engine
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship
from dotenv import load_dotenv
from create_db import Category, Customer, Order, OrderItem, Product, create_database


load_dotenv(dotenv_path=".env", override=True)


URL = "https://dst-de.s3.eu-west-3.amazonaws.com/extract_async.json"

RAW_DATA_PATH = Path("./dataset.json")

COLONNES_A_NETTOYER_NA = ['personal.country',
'personal.gender',
'personal.marital_status',
'company.name',
'company.num_employees',
'company.benefits',
'company.main_area_of_expertise',
'company.headquarters',
'job.department'
]

def telecharger_dataset(url : str) :
    try:
        r = requests.get(url= url, timeout=20)
        r.raise_for_status()              # lève HTTPError si 4xx/5xx
    except requests.exceptions.HTTPError as e:
        print(f"\nErreur HTTP : {e}")
    except requests.exceptions.ConnectionError:
        print("Erreur de connexion")
    except requests.exceptions.Timeout:
        print("Timeout")
    return r.json()



def explorer_json(obj, indent=0, racine :str = "employees"):
    prefix = "  " * indent
    if isinstance(obj, dict):
        for k, v in obj.items():
            print(f"{prefix}[dict] {k}: {type(v).__name__}")
            explorer_json(obj=v, indent=indent + 1)
    elif isinstance(obj, list):
        print(f"{prefix}[liste de {len(obj)} éléments]")
        for k, v in obj[0].items():
            print(f"{prefix}[dict] {k}: {type(v).__name__}")
            explorer_json(obj=v, indent=indent + 1)
    else:
        print(f"{prefix}→ {repr(obj)}")


def normaliser(dataset : list):
    return pd.json_normalize(dataset)

def inverser_age(df: pd.DataFrame) :
    df["personal.age"] = df["personal.age"].abs()
    return df

def drop_col_num_erreur(df: pd.DataFrame):
    df = df[df["experience.experience_years"] >= 0]
    return df

def clean_columns(df, sep='.'):
    df = df.copy()
    df.columns = [c.replace(sep, '_') if isinstance(c, str) else c for c in df.columns]
    return df







if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--input", type=Path, default=RAW_DATA_PATH)
    args = parser.parse_args()
    print("lancement du script")
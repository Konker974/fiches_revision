"""
etl.py - Extraction + Transformation (partie II.I, Q.8)

Version "script" du notebook exploration.ipynb :
  1. télécharge le fichier JSON du data lake      (Q.1)
  2. le lit dans un dictionnaire Python           (Q.2)
  3. aplatit la liste "employees"                  (Q.3)
  4. nettoie chaque ligne                          (Q.5 -> Q.7)
  5. renvoie un DataFrame propre (rien n'est écrit sur disque)

Les fonctions sont réutilisées par ingest.py (ingestion ligne par ligne).
Usage : python etl.py
"""
import json
import logging
import os
from datetime import date, datetime

import pandas as pd
import requests

logging.basicConfig(level=logging.INFO, format="%(levelname)s - %(message)s")
log = logging.getLogger(__name__)

DATA_URL = "https://dst-de.s3.eu-west-3.amazonaws.com/extract_async.json"
DATA_PATH = os.path.join(os.path.dirname(__file__), "data", "extract_async.json")


# --------------------------------------------------------------------------- #
# Extraction
# --------------------------------------------------------------------------- #
def download_file(url, dest_path, timeout=60):
    """Télécharge `url` vers `dest_path` (Q.1). Lève une exception si échec."""
    os.makedirs(os.path.dirname(dest_path) or ".", exist_ok=True)
    response = requests.get(url, timeout=timeout, stream=True)
    response.raise_for_status()  # erreur HTTP (404, 500...) -> exception
    with open(dest_path, "wb") as f:
        for chunk in response.iter_content(chunk_size=1024 * 1024):
            f.write(chunk)
    log.info("Fichier téléchargé : %s", dest_path)
    return dest_path


def load_employees(path):
    """Lit le JSON et renvoie la liste `employees` (Q.2)."""
    with open(path, encoding="utf-8") as f:
        data = json.load(f)  # json.JSONDecodeError si le fichier est corrompu
    if not isinstance(data, dict) or "employees" not in data:
        raise ValueError("Format inattendu : clé 'employees' absente")
    return data["employees"]


def unique_keys(records, sep="_"):
    """Liste des keys uniques (imbriquées comprises) de la liste `records` (Q.2)."""
    keys = []
    for record in records:
        for key in _flatten_one(record, sep=sep):
            if key not in keys:
                keys.append(key)
    return keys


# --------------------------------------------------------------------------- #
# Aplatissement (Q.3)
# --------------------------------------------------------------------------- #
def _flatten_one(record, parent="", sep="_"):
    """Aplatit un dictionnaire : {"A": {"B": 1}} -> {"A_B": 1}."""
    flat = {}
    for key, value in record.items():
        name = f"{parent}{sep}{key}" if parent else key
        if isinstance(value, dict):
            flat.update(_flatten_one(value, name, sep))
        else:
            flat[name] = value
    return flat


def flatten(records, sep="_"):
    """
    Aplatit une liste de dictionnaires imbriqués.
    - les clés imbriquées sont concaténées avec `sep`
    - toutes les lignes ont les mêmes colonnes (None si la clé est absente)
    - si une clé est à la fois une valeur simple ET un parent ailleurs
      (ex: "A": 4 et "A": {"A": 0}), la valeur simple est renommée "A*"
    """
    flats = [_flatten_one(r, sep=sep) for r in records]

    # noms qui servent de "parent" dans au moins une ligne (A dans A_A)
    parents = set()
    for r in records:
        parents |= _parent_names(r, sep=sep)

    # renommage des collisions puis collecte de toutes les colonnes
    renamed, columns = [], []
    for flat in flats:
        row = {(k + "*" if k in parents else k): v for k, v in flat.items()}
        renamed.append(row)
        for k in row:
            if k not in columns:
                columns.append(k)

    return [{col: row.get(col) for col in columns} for row in renamed]


def _parent_names(record, parent="", sep="_"):
    names = set()
    for key, value in record.items():
        name = f"{parent}{sep}{key}" if parent else key
        if isinstance(value, dict):
            names.add(name)
            names |= _parent_names(value, name, sep)
    return names


# --------------------------------------------------------------------------- #
# Nettoyage d'une ligne (Q.5 -> Q.7), utilisé par le script ET par l'ingestion
# --------------------------------------------------------------------------- #
GENDER_MAP = {"m": "M", "male": "M", "f": "F", "female": "F"}


def _to_int(value):
    """Convertit en int, None si vide / non convertible."""
    if value is None or value == "":
        return None
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return None


DATE_FORMATS = ("%Y-%m-%d", "%d-%m-%Y")  # les 2 formats présents dans le fichier


def _to_date(value):
    """Convertit 'YYYY-MM-DD' ou 'DD-MM-YYYY' en date, None si invalide."""
    if not value:
        return None
    for fmt in DATE_FORMATS:
        try:
            return datetime.strptime(str(value), fmt).date()
        except ValueError:
            pass
    return None


def _empty_to_none(value):
    """Les chaînes vides sont des valeurs manquantes cachées."""
    if isinstance(value, str):
        value = value.strip()
    return value or None


def clean_record(row):
    """
    Nettoie une ligne aplatie et renvoie un dictionnaire aux noms de colonnes courts.
    Problèmes corrigés (voir notebook) :
      - genre écrit de 6 façons (M, Male, male...) -> M / F
      - chaînes vides dans marital_status / education_level -> None
      - âges et années d'expérience négatifs -> valeur absolue (erreur de signe)
      - salaire à 0 -> None (inconnu)
      - expérience impossible au regard de l'âge -> None
      - dates texte en 2 formats différents -> date
      - email vide -> None
    """
    age = _to_int(row.get("personal_age"))
    age = abs(age) if age is not None else None

    exp = _to_int(row.get("experience_experience_years"))
    exp = abs(exp) if exp is not None else None
    # on ne commence pas à travailler avant 14 ans
    if exp is not None and age is not None and exp > age - 14:
        exp = None

    salary = _to_int(row.get("job_salary"))
    if salary is not None and salary <= 0:
        salary = None

    gender = row.get("personal_gender")
    gender = GENDER_MAP.get(str(gender).strip().lower()) if gender else None

    certif = row.get("experience_has_certifications")

    return {
        "id": _to_int(row.get("id")),
        "first_name": _empty_to_none(row.get("personal_first_name")),
        "last_name": _empty_to_none(row.get("personal_last_name")),
        "email": _empty_to_none(row.get("personal_email")),
        "country": _empty_to_none(row.get("personal_country")),
        "age": age,
        "gender": gender,
        "marital_status": _empty_to_none(row.get("personal_marital_status")),
        "education_level": _empty_to_none(row.get("experience_education_level")),
        "experience_years": exp,
        "has_certifications": bool(certif) if certif is not None else None,
        "work_hours_per_week": _to_int(row.get("experience_work_hours_per_week")),
        "projects_completed": _to_int(row.get("experience_projects_completed")),
        # entreprise
        "company_name": _empty_to_none(row.get("company_name")),
        "company_num_employees": _to_int(row.get("company_num_employees")),
        "company_benefits": _empty_to_none(row.get("company_benefits")),
        "company_main_area_of_expertise": _empty_to_none(row.get("company_main_area_of_expertise")),
        "company_headquarters": _empty_to_none(row.get("company_headquarters")),
        # poste
        "salary": salary,
        "department": _empty_to_none(row.get("job_department")),
        "join_date": _to_date(row.get("job_join_date")),
        "position_level": _empty_to_none(row.get("job_position_level")),
        "performance_score": _to_int(row.get("job_performance_score")),
        "last_promotion_date": _to_date(row.get("job_last_promotion_date")),
    }


# --------------------------------------------------------------------------- #
# Validation du schéma (IV.I) : une ligne invalide lève SchemaError
# --------------------------------------------------------------------------- #
class SchemaError(ValueError):
    pass


POSITION_LEVELS = {"Junior", "Mid", "Senior"}


def validate_record(rec):
    """Vérifie qu'une ligne nettoyée respecte le schéma de la base."""
    if not isinstance(rec.get("id"), int) or rec["id"] < 0:
        raise SchemaError(f"id invalide : {rec.get('id')!r}")
    if rec["age"] is None or not 0 <= rec["age"] <= 120:
        raise SchemaError(f"id={rec['id']} : âge invalide {rec['age']!r}")
    if rec["gender"] not in ("M", "F", None):
        raise SchemaError(f"id={rec['id']} : genre invalide {rec['gender']!r}")
    if rec["company_name"]:  # contrôles propres au poste
        if rec["position_level"] not in POSITION_LEVELS:
            raise SchemaError(f"id={rec['id']} : niveau invalide {rec['position_level']!r}")
        score = rec["performance_score"]
        if score is not None and not 1 <= score <= 10:
            raise SchemaError(f"id={rec['id']} : score invalide {score!r}")
        if rec["join_date"] and rec["join_date"] > date.today():
            raise SchemaError(f"id={rec['id']} : date d'arrivée dans le futur")
    return rec


# --------------------------------------------------------------------------- #
# Pipeline complet (version DataFrame)
# --------------------------------------------------------------------------- #
def transform(records):
    """Aplatit, nettoie, valide et renvoie un DataFrame des employés des GAFAM."""
    clean_rows = []
    for row in flatten(records):
        try:
            clean_rows.append(validate_record(clean_record(row)))
        except Exception as e:  # erreur non prévue sur une ligne -> on la saute
            log.warning("Ligne ignorée : %s", e)

    df = pd.DataFrame(clean_rows)
    df = df.drop_duplicates(subset="id")
    # les personnes sans entreprise ne travaillent pas dans une GAFAM : hors périmètre
    df = df[df["company_name"].notna()].reset_index(drop=True)
    return df


def main():
    if not os.path.exists(DATA_PATH):
        download_file(DATA_URL, DATA_PATH)
    records = load_employees(DATA_PATH)
    log.info("%d lignes lues, keys : %s", len(records), unique_keys(records[:100]))
    df = transform(records)
    log.info("%d lignes après transformation", len(df))
    print(df.head())
    return df


if __name__ == "__main__":
    main()

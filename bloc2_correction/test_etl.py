"""
test_etl.py - Tests (partie IV.I)

Lancement : pytest -v
La base est simulée par SQLite en mémoire : pas besoin de Docker pour les tests.
"""
import pytest
from sqlalchemy import create_engine, func, select
from sqlalchemy.orm import Session

from database import Company, Employee, Job
from etl import SchemaError, clean_record, flatten, validate_record
from ingest import ingest


# Exemple brut proche du fichier source
RAW = {
    "id": 1,
    "personal": {"first_name": "Ana", "last_name": "Lopez", "email": "ana@apple.es",
                 "country": "Spain", "age": -30, "gender": "female",
                 "marital_status": ""},
    "company": {"name": "Apple", "num_employees": 154000, "benefits": "x",
                "main_area_of_expertise": "y", "headquarters": "z"},
    "job": {"salary": 0, "department": "HR", "join_date": "2020-01-01",
            "position_level": "Mid", "performance_score": 4,
            "last_promotion_date": None},
    "experience": {"experience_years": -5, "has_certifications": True,
                   "education_level": "PhD", "work_hours_per_week": 40,
                   "projects_completed": 3},
}


def test_flatten_exemple_du_sujet():
    data = [{"A": {"A": 0}, "B": 1}, {"B": 2, "C": 3}, {"A": 4}]
    assert flatten(data) == [
        {"A*": None, "A_A": 0, "B": 1, "C": None},
        {"A*": None, "A_A": None, "B": 2, "C": 3},
        {"A*": 4, "A_A": None, "B": None, "C": None},
    ]


def test_clean_record_corrige_les_anomalies():
    rec = clean_record(flatten([RAW])[0])
    assert rec["age"] == 30               # âge négatif -> valeur absolue
    assert rec["experience_years"] == 5
    assert rec["gender"] == "F"           # "female" -> "F"
    assert rec["marital_status"] is None  # "" -> None
    assert rec["salary"] is None          # 0 -> inconnu


def test_dates_deux_formats():
    raw = {**RAW, "job": {**RAW["job"], "join_date": "16-01-2022"}}
    assert str(clean_record(flatten([raw])[0])["join_date"]) == "2022-01-16"


def test_validate_rejette_un_mauvais_schema():
    rec = clean_record(flatten([RAW])[0])
    rec["position_level"] = "Boss"
    with pytest.raises(SchemaError):
        validate_record(rec)


@pytest.fixture
def engine():
    return create_engine("sqlite://")  # base en mémoire


def count(engine, model):
    with Session(engine) as s:
        return s.scalar(select(func.count()).select_from(model))


def test_ingestion_sans_doublons(engine):
    sans_job = {"id": 2, "personal": {"age": 20, "gender": "M"},
                "experience": {"education_level": "High School"}}
    stats = ingest([RAW, RAW, sans_job], engine)       # RAW en double dans le fichier
    assert stats == {"inserted": 2, "duplicates": 1, "invalid": 0}

    ingest([RAW, sans_job], engine)                    # 2e lancement : rien de neuf
    assert count(engine, Employee) == 2
    assert count(engine, Job) == 1                     # la personne sans entreprise n'a pas de poste
    assert count(engine, Company) == 1


def test_ingestion_ignore_les_lignes_invalides(engine):
    stats = ingest([{"id": "abc"}, {"personal": {"age": 30}}], engine)
    assert stats["invalid"] == 2
    assert count(engine, Employee) == 0

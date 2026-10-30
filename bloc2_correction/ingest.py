"""
ingest.py - Ingestion des données dans MySQL via l'ORM (partie II.II, Q.6 + IV.I)

On part directement du fichier JSON initial : chaque ligne est aplatie,
nettoyée et validée au fur et à mesure, puis insérée via SQLAlchemy.

Garde-fous :
  - ligne ne respectant pas le schéma -> ignorée et loguée
  - id déjà vu (dans le fichier ou déjà en base) -> ignoré (pas de doublon)
  - entreprises créées une seule fois (cache par nom)

Usage : python ingest.py
"""
import logging
import os

from sqlalchemy import select
from sqlalchemy.orm import Session

from database import Company, Employee, Job, create_tables, get_engine
from etl import (DATA_PATH, DATA_URL, clean_record, download_file, flatten,
                 load_employees, validate_record)

log = logging.getLogger(__name__)

BATCH_SIZE = 5000  # commit par paquets pour aller plus vite


def get_or_create_company(session, cache, rec):
    """Renvoie l'entreprise de la ligne, en la créant si besoin."""
    name = rec["company_name"]
    if name not in cache:
        company = session.scalar(select(Company).where(Company.name == name))
        if company is None:
            company = Company(
                name=name,
                num_employees=rec["company_num_employees"],
                benefits=rec["company_benefits"],
                main_area_of_expertise=rec["company_main_area_of_expertise"],
                headquarters=rec["company_headquarters"],
            )
            session.add(company)
        cache[name] = company
    return cache[name]


def ingest(records, engine):
    """Insère les `records` bruts (liste issue du JSON). Renvoie les compteurs."""
    create_tables(engine)
    stats = {"inserted": 0, "duplicates": 0, "invalid": 0}

    with Session(engine) as session:
        # ids déjà présents en base : relancer le script n'insère pas de doublons
        seen_ids = set(session.scalars(select(Employee.id)))
        companies = {}

        for i, raw in enumerate(records, start=1):
            try:
                # transformation ligne par ligne (flatten attend une liste)
                rec = validate_record(clean_record(flatten([raw])[0]))
            except Exception as e:
                stats["invalid"] += 1
                log.warning("Ligne invalide ignorée : %s", e)
                continue

            if rec["id"] in seen_ids:
                stats["duplicates"] += 1
                continue
            seen_ids.add(rec["id"])

            employee = Employee(
                id=rec["id"],
                first_name=rec["first_name"],
                last_name=rec["last_name"],
                email=rec["email"],
                country=rec["country"],
                age=rec["age"],
                gender=rec["gender"],
                marital_status=rec["marital_status"],
                education_level=rec["education_level"],
                experience_years=rec["experience_years"],
                has_certifications=rec["has_certifications"],
                work_hours_per_week=rec["work_hours_per_week"],
                projects_completed=rec["projects_completed"],
            )
            # un poste n'est créé que si la personne travaille dans une entreprise
            if rec["company_name"]:
                employee.job = Job(
                    company=get_or_create_company(session, companies, rec),
                    salary=rec["salary"],
                    department=rec["department"],
                    join_date=rec["join_date"],
                    position_level=rec["position_level"],
                    performance_score=rec["performance_score"],
                    last_promotion_date=rec["last_promotion_date"],
                )
            session.add(employee)
            stats["inserted"] += 1

            if i % BATCH_SIZE == 0:
                session.commit()
                log.info("%d lignes traitées", i)

        session.commit()
    return stats


def main():
    if not os.path.exists(DATA_PATH):
        download_file(DATA_URL, DATA_PATH)
    stats = ingest(load_employees(DATA_PATH), get_engine())
    log.info("Ingestion terminée : %s", stats)


if __name__ == "__main__":
    main()

"""
database.py - Implémentation de la base de données (partie II.II, Q.3 -> Q.5)

Schéma (3 tables, voir README.md) :
    companies 1 ---- n jobs n ---- 1 employees
    (un employé a au plus un poste, un poste appartient à une entreprise)

Usage : python database.py   -> crée les tables dans MySQL
"""
import os

from dotenv import load_dotenv
from sqlalchemy import (Boolean, Column, Date, ForeignKey, Integer, String,
                        create_engine)
from sqlalchemy.orm import declarative_base, relationship

load_dotenv()  # charge le fichier .env (identifiants hors du code, Q.4)

Base = declarative_base()


class Company(Base):
    __tablename__ = "companies"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(50), unique=True, nullable=False)
    num_employees = Column(Integer)
    benefits = Column(String(255))
    main_area_of_expertise = Column(String(100))
    headquarters = Column(String(100))

    jobs = relationship("Job", back_populates="company")


class Employee(Base):
    __tablename__ = "employees"

    id = Column(Integer, primary_key=True, autoincrement=False)  # id du fichier source
    first_name = Column(String(100))
    last_name = Column(String(100))
    email = Column(String(255))
    country = Column(String(50))
    age = Column(Integer, nullable=False)
    gender = Column(String(1))
    marital_status = Column(String(20))
    education_level = Column(String(30))
    experience_years = Column(Integer)
    has_certifications = Column(Boolean)
    work_hours_per_week = Column(Integer)
    projects_completed = Column(Integer)

    job = relationship("Job", back_populates="employee", uselist=False)


class Job(Base):
    __tablename__ = "jobs"

    id = Column(Integer, primary_key=True, autoincrement=True)
    # unique=True : un employé ne peut pas avoir deux postes (pas de doublon)
    employee_id = Column(Integer, ForeignKey("employees.id"), unique=True, nullable=False)
    company_id = Column(Integer, ForeignKey("companies.id"), nullable=False)
    salary = Column(Integer)
    department = Column(String(30))
    join_date = Column(Date)
    position_level = Column(String(10))
    performance_score = Column(Integer)
    last_promotion_date = Column(Date)

    employee = relationship("Employee", back_populates="job")
    company = relationship("Company", back_populates="jobs")


def get_engine():
    """Crée la connexion MySQL à partir des variables d'environnement."""
    url = (
        f"mysql+pymysql://{os.environ['MYSQL_USER']}:{os.environ['MYSQL_PASSWORD']}"
        f"@{os.getenv('MYSQL_HOST', 'localhost')}:{os.getenv('MYSQL_PORT', '3306')}"
        f"/{os.environ['MYSQL_DATABASE']}?charset=utf8mb4"
    )
    return create_engine(url)


def create_tables(engine):
    """Crée les tables (si elles n'existent pas) en respectant les clés étrangères."""
    Base.metadata.create_all(engine)


if __name__ == "__main__":
    create_tables(get_engine())
    print("Tables créées :", list(Base.metadata.tables))

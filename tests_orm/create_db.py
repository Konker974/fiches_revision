
import argparse

import os
from pathlib import Path
from sqlalchemy import (
    CheckConstraint, DateTime, Float, ForeignKey, Integer, String,
    create_engine,
)
from sqlalchemy.engine import Engine
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship
from dotenv import load_dotenv

load_dotenv(dotenv_path=".env", override=True)


DATABASE_URL = os.environ.get(key='DATABASE_URL')


class Base(DeclarativeBase):
    pass


class Personnal(Base):
    __tablename__ = "personnal"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    company_id: Mapped[int] = mapped_column(ForeignKey("company.id"), nullable=False)
    
    personal_first_name: Mapped[str] = mapped_column(String(100), nullable=False)
    personal_last_name: Mapped[str] = mapped_column(String(100), nullable=False)
    personal_email: Mapped[str] = mapped_column(String(100), nullable=False)
    personal_country: Mapped[str] = mapped_column(String(100), nullable=False)
    personal_age: Mapped[int] = mapped_column(Integer, nullable=False)
    personal_gender: Mapped[str] = mapped_column(String(100), nullable=False)
    personal_marital_status: Mapped[str] = mapped_column(String(100), nullable=False)
    experience_experience_years: Mapped[float] = mapped_column(Float, nullable=False)
    experience_has_certifications: Mapped[str] = mapped_column(String(100), nullable=False)
    experience_education_level: Mapped[str] = mapped_column(String(100), nullable=False)
    experience_work_hours_per_week: Mapped[float] = mapped_column(Float, nullable=False)
    experience_projects_completed: Mapped[float] = mapped_column(Float, nullable=False)
    job_salary: Mapped[float] = mapped_column(Float, nullable=False)
    job_department: Mapped[str] = mapped_column(String(100), nullable=False)
    job_join_date: Mapped[str] = mapped_column(String(100), nullable=False)
    job_position_level: Mapped[str] = mapped_column(String(100), nullable=False)
    job_performance_score: Mapped[float] = mapped_column(Float, nullable=False)
    job_last_promotion_date: Mapped[str] = mapped_column(String(100), nullable=False)

    company: Mapped["Company"] = relationship(back_populates="personnal")

class Company(Base):
    __tablename__ = "company"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    company_name: Mapped[str] = mapped_column(String(100), nullable=False)
    company_num_employees: Mapped[float] = mapped_column(Float, nullable=False)
    company_benefits: Mapped[str] = mapped_column(String(100), nullable=False)
    company_main_area_of_expertise: Mapped[str] = mapped_column(String(100), nullable=False)
    company_headquarters: Mapped[str] = mapped_column(String(100), nullable=False)

    personnal: Mapped[list["Personnal"]] = relationship(back_populates="company")





def get_engine(url: str) -> Engine:
    if not DATABASE_URL and url is None :
        print("erreur database url")
    else :
        return create_engine(url, pool_size=5, max_overflow=10, pool_timeout=30)



def create_database(url: str = DATABASE_URL) -> Engine:
    engine = get_engine(url)
    Base.metadata.create_all(engine)
    print("Tables créées")
    return engine



if __name__ == "__main__":
    print("création de la base")
    create_database()
    

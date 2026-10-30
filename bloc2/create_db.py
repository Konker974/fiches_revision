"""Création de la base relationnelle avec l'ORM SQLAlchemy 2.0.

Modèle (3e forme normale) :

    categories 1──n products 1──n order_items n──1 orders n──1 customers

- categories  : catégorie produit
- products    : produit (nom unique, prix catalogue)
- customers   : client et son adresse
- orders      : en-tête de commande (dates, paiement, statut, lieu de livraison)
- order_items : lignes de commande (produit, quantité, montant)

Usage :
    python create_db.py          # crée les tables manquantes
    python create_db.py --reset  # supprime puis recrée toutes les tables
"""
import argparse
from datetime import datetime

from sqlalchemy import (
    CheckConstraint, DateTime, Float, ForeignKey, Integer, String,
    create_engine,
)
from sqlalchemy.engine import Engine
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship

from config import BASE_DIR, DATABASE_URL, get_logger

logger = get_logger("create_db")


class Base(DeclarativeBase):
    pass


class Category(Base):
    __tablename__ = "categories"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)  # id source conservé
    name: Mapped[str] = mapped_column(String(100), nullable=False)

    products: Mapped[list["Product"]] = relationship(back_populates="category")


class Product(Base):
    __tablename__ = "products"
    __table_args__ = (CheckConstraint("price > 0", name="ck_product_price"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(150), unique=True, nullable=False)
    price: Mapped[float] = mapped_column(Float, nullable=False)
    category_id: Mapped[int] = mapped_column(ForeignKey("categories.id"), index=True)

    category: Mapped[Category] = relationship(back_populates="products")
    items: Mapped[list["OrderItem"]] = relationship(back_populates="product")


class Customer(Base):
    __tablename__ = "customers"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)  # id source conservé
    firstname: Mapped[str] = mapped_column(String(100), nullable=False)
    lastname: Mapped[str] = mapped_column(String(100), nullable=False)
    street: Mapped[str | None] = mapped_column(String(200))
    city: Mapped[str | None] = mapped_column(String(100))
    state: Mapped[str | None] = mapped_column(String(50))
    zipcode: Mapped[str | None] = mapped_column(String(10))
    country: Mapped[str | None] = mapped_column(String(50))

    orders: Mapped[list["Order"]] = relationship(back_populates="customer")


class Order(Base):
    __tablename__ = "orders"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)  # id source conservé
    customer_id: Mapped[int] = mapped_column(ForeignKey("customers.id"), index=True)
    order_date: Mapped[datetime] = mapped_column(DateTime, nullable=False, index=True)
    shipping_date: Mapped[datetime | None] = mapped_column(DateTime)
    payment_type: Mapped[str] = mapped_column(String(20), nullable=False)
    status: Mapped[str] = mapped_column(String(30), nullable=False, index=True)
    market: Mapped[str] = mapped_column(String(30), nullable=False)
    # Lieu de livraison (différent de l'adresse du client)
    country: Mapped[str | None] = mapped_column(String(100))
    state: Mapped[str | None] = mapped_column(String(100))
    region: Mapped[str | None] = mapped_column(String(100))
    city: Mapped[str | None] = mapped_column(String(100))

    customer: Mapped[Customer] = relationship(back_populates="orders")
    items: Mapped[list["OrderItem"]] = relationship(
        back_populates="order", cascade="all, delete-orphan"
    )


class OrderItem(Base):
    __tablename__ = "order_items"
    __table_args__ = (
        CheckConstraint("quantity > 0", name="ck_item_quantity"),
        CheckConstraint("sales >= 0", name="ck_item_sales"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    order_id: Mapped[int] = mapped_column(ForeignKey("orders.id"), index=True)
    product_id: Mapped[int] = mapped_column(ForeignKey("products.id"), index=True)
    quantity: Mapped[int] = mapped_column(Integer, nullable=False)
    unit_price: Mapped[float] = mapped_column(Float, nullable=False)  # prix figé à la commande
    sales: Mapped[float] = mapped_column(Float, nullable=False)

    order: Mapped[Order] = relationship(back_populates="items")
    product: Mapped[Product] = relationship(back_populates="items")


def get_engine(url: str = DATABASE_URL) -> Engine:
    if url.startswith("sqlite:///"):
        (BASE_DIR / "data").mkdir(parents=True, exist_ok=True)
    return create_engine(url, future=True)


def create_database(reset: bool = False, url: str = DATABASE_URL) -> Engine:
    engine = get_engine(url)
    if reset:
        logger.warning("Suppression de toutes les tables")
        Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    logger.info("Tables prêtes (%s) : %s", engine.url.render_as_string(hide_password=True),
                ", ".join(Base.metadata.tables))
    return engine


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--reset", action="store_true", help="supprime et recrée les tables")
    args = parser.parse_args()
    create_database(reset=args.reset)

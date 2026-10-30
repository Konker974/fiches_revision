"""Petit module métier servant d'exemple pour les tests."""
import json
import os
from urllib.request import urlopen

TVA = 0.20


def prix_ttc(prix_ht: float, taux: float = TVA) -> float:
    if prix_ht < 0:
        raise ValueError("Le prix HT doit être positif")
    return round(prix_ht * (1 + taux), 2)


def get_database_url() -> str:
    url = os.getenv("DATABASE_URL")
    if url is None:
        raise RuntimeError("DATABASE_URL non définie")
    return url


def charger_commandes(chemin) -> list[dict]:
    with open(chemin, encoding="utf-8") as f:
        return json.load(f)


def get_taux_change(devise: str) -> float:
    """Appelle une API externe : réseau, lenteur, quota... à ne PAS appeler en test."""
    with urlopen(f"https://api.exemple.com/taux/{devise}", timeout=5) as reponse:
        return json.load(reponse)["taux"]


def convertir(montant_eur: float, devise: str) -> float:
    return round(montant_eur * get_taux_change(devise), 2)


class Notificateur:
    """Envoie de vrais messages (e-mail, Slack...)."""
    def envoyer(self, destinataire: str, message: str) -> bool:
        raise NotImplementedError("envoi réel")


def traiter_commande(commande: dict, notificateur: Notificateur) -> float:
    """Calcule le total et alerte l'équipe fraude au-delà de 1000 €."""
    total = sum(l["prix"] * l["qte"] for l in commande["lignes"])
    if total > 1000:
        notificateur.envoyer("fraude@shop.fr", f"Commande {commande['id']} : {total} €")
    return total

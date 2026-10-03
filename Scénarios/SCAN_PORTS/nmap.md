# Scénario: Détection d'un Scan de Ports (Nmap)

Ce scénario démontre la capacité de Snort à détecter une tentative de scan réseau menée par un attaquant

## 1. Règle de détection (Snort)
Pour détecter un scan de ports, nous cherchons à identifier un volume anormalement élevé de paquets TCP avec le flag `SYN` (demande de synchronisation) provenant d'une même source en un temps très court.

**Fichier modifié :** `/etc/snort/rules/local.rules`
**Règle ajoutée :**
```
# 1 - Scan de ports par nmap classique
alert tcp any any -> $HOME_NET any (msg:"SCAN DE PORTS detecte - nmap"; flags:S; detection_filter:track by_src, count 5, seconds 5; sid:1000002; rev:1; )

# 2 - Scan de ports XMAS (Nmap -sX)
alert tcp any any -> $HOME_NET any (msg:"Scan de ports XMAS detecte"; flags:FPU; sid:1000008; rev:1;)

# 3 - Scan de ports NULL (Nmap -sN)
alert tcp any any -> $HOME_NET any (msg:"Scan de ports NULL detecte"; flags:0; sid:1000009; rev:1;)

# 4 - Scan de ports FIN (Nmap -sF)
alert tcp any any -> $HOME_NET any (msg:"Scan de ports FIN detecte - nmap -sF"; flags:F; sid:1000010; rev:1;)

```
*Explication de la règle : Génère une alerte si plus de 5 paquets SYN sont envoyés par la même IP source vers n'importe quel port de notre réseau en moins de 5 secondes.*

## 2. Reproduction de l'attaque (Guide d'utilisation)
**Prérequis :** L'attaquant est sur la VM Kali Linux et cible la VM Ubuntu (192.168.56.101).

1. Sur la VM Ubuntu, assurez-vous que Snort est relancé pour prendre en compte la règle :

   ```sudo systemctl restart snort```
2. Sur la VM Kali, lancez un scan avec `nmap` :

   ```sudo nmap -sS -p 1-1000 192.168.56.101```

## 3. Visualisation et Analyse dans Kibana

![Capture d'écran Kibana des alertes Snort](./images/nmap_classique.png)

![Capture d'écran Kibana des alertes Snort](./images/nmap_xmas.png)

![Capture d'écran Kibana des alertes Snort](./images/nmap_null.png)

![Capture d'écran Kibana des alertes Snort](./images/nmap_fin.png)

### Comment lire cette capture ?
* **Timestamp :** La date avec l'heure de l'attaque est enregistrée, correspondant à l'exécution de la commande Nmap.

* **Message :** On observe un grand nombre d'alterte  `SCAN DE PORTS detecte`. 

## Théorie : Comprendre les Scans Nmap et leur Détection

Dans le cadre de nos scénarios d'intrusion, nous utilisons Nmap pour analyser le réseau. Chaque type de scan a un comportement spécifique que notre IDS (Snort) doit analyser au niveau des paquets TCP.

### 1. Le Scan TCP (Scan classique)
* **Commande Nmap :** `nmap -sT` (Scan complet) ou `nmap -sS` (Scan furtif SYN)
* **Ce que fait l'attaque :** L'attaquant cherche les ports ouverts (ex: port 80, port 22). Il envoie des paquets demandant à ouvrir une connexion (`SYN`). C'est le scan le plus courant mais aussi le plus "bruyant".
* **Comment on le détecte :** On configure Snort pour compter le nombre de paquets TCP ayant le flag **SYN** activé (`flags:S;`) sur une courte période.

### 2. Le Scan XMAS (Scan de Noël)
* **Commande Nmap :** `nmap -sX 192.168.56.101`
* **Ce que fait l'attaque :** C'est un scan furtif pour contourner les pare-feux basiques. Il s'appelle "XMAS" car l'attaquant modifie le paquet TCP en activant simultanément plusieurs flags (FIN, PSH, URG). Selon la façon dont le serveur rejette ce paquet anormal, l'attaquant déduit si le port est ouvert ou fermé.
* **Comment on le détecte :** Snort analyse les entêtes TCP. Si les trois flags sont vus en même temps (`flags:FPU;`), c'est obligatoirement malveillant.

### 3. Le Scan NULL (Scan vide)
* **Commande Nmap :** `nmap -sN 192.168.56.101`
* **Ce que fait l'attaque :** C'est l'inverse du scan XMAS. L'attaquant envoie un paquet TCP complètement vide, sans aucun flag activé. Cela viole les standards du protocole TCP/IP.
* **Comment on le détecte :** Snort possède une option pour vérifier l'absence totale de flags (`flags:0;`).

### 4. Le Scan FIN (Scan de fin)
* **Commande Nmap :** `nmap -sF 192.168.56.101`
* **Ce que fait l'attaque :** Au lieu d'ouvrir une connexion proprement (SYN), l'attaquant envoie un paquet demandant de *fermer* une connexion qui n'a jamais existé (flag FIN). Les systèmes Linux répondent différemment si le port est fermé ou ouvert.
* **Comment on le détecte :** La règle Snort cible spécifiquement les paquets isolés ne contenant que le flag de terminaison (`flags:F;`).

## Limites et Améliorations (Analyse)

Bien que nos règles couvrent la majorité des scans Nmap classiques et furtifs, une limite subsiste face aux attaques dites "Low and Slow". 

- **Limite actuelle :** Un attaquant  pourrait utiliser Nmap avec l'option `-T1` (Sneaky) ou `-T0` (Paranoid). Ces options forcent Nmap à attendre plusieurs dizaines de secondes, voire plusieurs minutes, entre chaque paquet envoyé. Notre règle de détection principale (qui cherche 5 paquets en 5 secondes) ne se déclenchera pas.
- **Amélioration possible :** Pour contrer cela, il faudrait ajouter une règle supplémentaire avec une fenêtre de temps beaucoup plus large (ex: `count 10, seconds 120`). Cependant, en environnement réel, cela augmenterait le risque de "faux positifs" si un utilisateur légitime a des problèmes de connexion et tente de se reconnecter lentement.


#### Sources
https://www.hackingarticles.in/detect-nmap-scan-using-snort/
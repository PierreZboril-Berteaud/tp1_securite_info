# Guide d'utilisation : Script scan de ports

Ce script automatise le lancement de 4 techniques de scans réseau différentes (SYN, XMAS, NULL, FIN)depuis la machine attaquante vers la cible. Il permet de valider le bon déclenchement de nos règles de détection Snort.

## 1. Comment exécuter le script

**Prérequis :** Ce script doit être exécuté depuis la VM d'attaque (**Kali Linux**).

1. Ouvrez un terminal sur votre machine Kali, dans le dossier où se trouve le script.
2. Rendez le script exécutable avec la commande suivante :
   
   ```chmod +x nmap.sh```
3. Lancez le script :

   ```sudo ./nmap.sh```
4. Laissez le script s'exécuter. Il effectuera une pause de 5 secondes entre chaque attaque pour générer des timestamp bien distincts.

## 2. Comment lire les alertes dans Kibana

Une fois le script terminé, basculez sur votre navigateur pour vérifier la remontée des alertes.

1. **Ouvrir l'interface :** Accédez à Kibana via l'URL 

```http://192.168.56.101:5601 ```

2. **Aller dans Discover :** Ouvrez le menu principal (les trois lignes en haut à gauche) et cliquez sur **Discover** (dans la section *Analytics*).

3. **Sélectionner l'index :** Vérifiez en haut à gauche que votre Data View `logs-securite-*` est bien sélectionnée.

4. **Ajuster le temps :** En haut à droite, réglez la fenêtre de temps sur **Last 15 minutes**, puis cliquez sur **Refresh**.

5. **Filtrer le trafic :** Pour cacher les logs normaux du système et ne voir que les attaques, tapez le mot `SCAN` ou `nmap` dans la barre de recherche centrale, puis appuyez sur Entrée.

### Que devez-vous observer ?

Dans la liste chronologique des événements, regardez le contenu du champ `message`. Vous y verrez les 4 alertes de sécurité créées par Snort, correspondant exactement aux 4 étapes du script :

* `SCAN DE PORTS detecte - nmap`
* `Scan de ports XMAS detecte`
* `Scan de ports NULL detecte`
* `Scan de ports FIN detecte - nmap -sF`

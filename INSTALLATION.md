# Projet pratique 1 : Système de détection d'anomalies et degestion de logs pour la sécurité des réseaux


Système de détection d'intrusions (Snort) couplé à une centralisation et de visualisation de logs (syslog-ng → Elasticsearch → Kibana), déployé sur une VM Ubuntu Server et testé depuis une VM Kali Linux.

## Sommaire

- [Architecture](#architecture)
- [Prérequis](#prérequis)
- [1. Configuration réseau](#1-configuration-réseau)
- [2. Installation des services de base](#2-installation-des-services-de-base-vm-serveurelk)
- [3. Installation et configuration de Snort (IDS)](#3-installation-et-configuration-de-snort-ids)
- [4. Installation et configuration de syslog-ng](#4-installation-et-configuration-de-syslog-ng)
- [5. Installation et configuration d'Elasticsearch](#5-installation-et-configuration-delasticsearch)
- [6. Installation et configuration de Kibana](#6-installation-et-configuration-de-kibana)
- [7. Liaison syslog-ng → Elasticsearch](#7-liaison-de-syslog-ng-vers-elasticsearch)
- [8. Affichage des logs dans Kibana](#8-affichage-des-logs-dans-kibana)

## Architecture

Par souci de simplicité et de ressources matérielles, les rôles « Serveur » et « ELK » sont fusionnés sur une seule VM, contrairement à une architecture de production où ces rôles seraient séparés.

| VM | Rôle | OS 
|---|---|---|
| VM1 — Serveur+ELK | Apache, SSH, Snort, syslog-ng, Elasticsearch, Kibana | Ubuntu Server 22.04/24.04 LTS
| VM2 — Attaquant | Outils d'attaque (nmap, hydra, nikto, hping3, sqlmap) | Kali Linux (image VM pré-construite)

**Flux de données :**

```
Snort / Apache / SSH  →  syslog-ng  →  Elasticsearch (port 9200)  → Kibana(port 5601)
   (génération)          (collecte)       (stockage)      (visualisation)
```

## Prérequis

- VirtualBox avec deux VM : Ubuntu Server (22.04/24.04 LTS) et Kali Linux.
- Chaque VM configurée avec deux cartes réseau :
  - **Adaptateur 1 — NAT** : accès Internet (`apt update`, `apt install`).
  - **Adaptateur 2 — Réseau privé hôte (Host-only, vboxnet0)** : communication entre les deux VM sur `192.168.56.0/24`.

## 1. Configuration réseau

Adresses IP fixes retenues :

| Machine | Interface | Adresse IP |
|---|---|---|
| VM1 Ubuntu | enp0s3 (NAT) | DHCP |
| VM1 Ubuntu | enp0s8 (Host-only) | 192.168.56.101/24 |
| VM2 Kali | Host-only | 192.168.56.102/24 (via nmcli) |

Fichier `/etc/netplan/50-cloud-init.yaml` sur la VM Ubuntu (indentation en espaces uniquement, jamais de tabulation) :

```yaml
network:
  ethernets:
    enp0s3:
      dhcp4: true
    enp0s8:
      dhcp4: false
      addresses:
        - 192.168.56.101/24
  version: 2
```

```bash
sudo netplan apply
ip a   # vérifier que enp0s8 est UP avec 192.168.56.101
```

**Test de fonctionnement** depuis Kali :

```bash
ping -c 4 192.168.56.101
```

## 2. Installation des services de base (VM Serveur+ Elasticsearch + kibana)

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y apache2 php libapache2-mod-php openssh-server
```

Vérification :

```bash
sudo systemctl status apache2 ssh   # doivent être "active"
```

## 3. Installation et configuration de Snort (IDS)

### 3.1 Installation

```bash
sudo apt install -y snort
```

Valeurs cibles : interface à surveiller `enp0s8`, réseau protégé (HOME_NET) `192.168.56.0/24`. À corriger dans `/etc/snort/snort.debian.conf` :

```
DEBIAN_SNORT_INTERFACE="enp0s8"
DEBIAN_SNORT_HOME_NET="192.168.56.0/24"
```

### 3.2 Règle de test ICMP

Dans `/etc/snort/rules/local.rules` :

```
alert icmp any any -> $HOME_NET any (msg:"TEST ICMP Ping detecte"; sid:1000001; rev:1;)
```

### 3.3 Validation

Snort écrit ses alertes dans `/var/log/snort/snort.alert.fast` (pas dans `/var/log/snort/alert`) :

```bash
sudo systemctl restart snort
sudo tail -f /var/log/snort/snort.alert.fast
```

Depuis Kali : `ping -c 4 192.168.56.101` doit faire apparaître l'alerte "TEST ICMP Ping detecte" (sid:1000001).

## 4. Installation et configuration de syslog-ng

### 4.1 Installation

```bash
sudo apt update
sudo apt install -y syslog-ng
```

### 4.2 Structure

Fichier `/etc/syslog-ng/syslog-ng.conf`, structuré en quatre types de blocs :

- **source** : d'où proviennent les logs (fichiers, réseau)
- **filter** *(optionnel)* : trie/isole certains événements
- **destination** : où envoyer les logs
- **log** : relie source(s), filtre(s) et destination(s)

### 4.3 Configuration Apache, Snort, SSH

`s_src` est la source système par défaut d'Ubuntu : elle inclut déjà `/var/log/auth.log` (donc SSH). Ajouter à la fin du fichier :

```
# --- Sources ---
source s_apache {
    file("/var/log/apache2/access.log");
    file("/var/log/apache2/error.log");
};

source s_snort {
    file("/var/log/snort/snort.alert.fast" flags(no-parse));
};

# --- Destination locale (test / debogage) ---
destination d_local_central {
    file("/var/log/syslog-ng-central.log");
};

# --- Liaison ---
log {
    source(s_apache);
    source(s_snort);
    source(s_src);
    destination(d_local_central);
};
```

### 4.4 Vérification et redémarrage

```bash
sudo syslog-ng -s                     # vérifie la syntaxe
sudo systemctl restart syslog-ng
sudo systemctl status syslog-ng
sudo tail -f /var/log/syslog-ng-central.log
```

## 5. Installation et configuration d'Elasticsearch

### 5.1 Ajout du dépôt officiel

```bash
sudo apt install -y apt-transport-https curl gnupg

curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --yes --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-8.x.list

sudo apt update
```

### 5.2 Installation

```bash
sudo apt install -y elasticsearch
```

### 5.3 Désactivation de la sécurité (laboratoire uniquement)

Dans `/etc/elasticsearch/elasticsearch.yml`, remplacer :

```
xpack.security.enabled: false
```



### 5.4 Démarrage et test

```bash
sudo systemctl enable --now elasticsearch
sudo systemctl status elasticsearch
curl -X GET "http://127.0.0.1:9200"   # doit renvoyer un JSON
```

## 6. Installation et configuration de Kibana

```bash
sudo apt install -y kibana
sudo nano /etc/kibana/kibana.yml
```

Décommenter/modifier :

```yaml
server.host: "0.0.0.0"
elasticsearch.hosts: ["http://127.0.0.1:9200"]
```

```bash
sudo systemctl enable --now kibana
sudo systemctl status kibana
sudo ss -tulpn | grep 5601
```

La VM Ubuntu n'a pas d'interface graphique : ouvrir l'interface web depuis la VM Kali ou la machine hôte (démarrage lent) :

```
http://192.168.56.101:5601
```

## 7. Liaison de syslog-ng vers Elasticsearch


```bash
sudo nano /etc/syslog-ng/syslog-ng.conf
```

```
destination d_elastic {
    http(
        url("http://127.0.0.1:9200/_bulk")
        method("POST")
        headers("Content-Type: application/x-ndjson")
        body("{\"create\": {\"_index\": \"logs-securite-${YEAR}.${MONTH}.${DAY}\"} }\n{\"message\": \"${MSG}\"}\n")
    );
};

log {
    source(s_apache);
    source(s_snort);
    source(s_src);
    destination(d_local_central);
    destination(d_elastic);
};
```

```bash
sudo syslog-ng -s
sudo systemctl restart syslog-ng
sudo systemctl status syslog-ng
```

## 8. Affichage des logs dans Kibana

1. Ouvrir `http://192.168.56.101:5601`.
2. Menu principal → **Stack Management** → **Data Views**.
3. **Create data view**.
4. Motif : `logs-securite-*`.
5. Champ de temps : `@timestamp`, puis **Save data view to Kibana**.
6. **Analytics → Discover**, période réglée sur "Today" ou "Last 24 hours".

Filtrer avec `ICMP` ou `snort` dans la barre de recherche pour isoler les alertes parmi le reste des journaux.

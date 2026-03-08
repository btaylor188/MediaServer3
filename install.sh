#!/bin/bash

set -e

# Remove .env files on exit (success or failure)
cleanup() {
    rm -f ./frontend/.env ./backend/.env ./infrastructure/.env
}
trap cleanup EXIT

####### Define Variables ######
echo "What is the domain name?"
read DOMAINNAME

echo "Enter path for Docker data (e.g. /mnt/docker):"
read DOCKERPATH
sudo mkdir -p "$DOCKERPATH"

echo "Enter path for temp processing (e.g. /mnt/processing):"
read PROCESSPATH
sudo mkdir -p "$PROCESSPATH"

echo "Enter path for Plex Media:"
read MEDIAPATH
sudo mkdir -p "$MEDIAPATH"

echo "Enter Claim token from plex.tv/claim:"
read PLEXCLAIM

echo "PIA VPN Username:"
read PIAUSER

echo "PIA VPN Password:"
read -s PIAPASS
echo

echo "Enter Local Network in CIDR Notation (e.g. 192.168.1.0/24):"
read LOCALNET

echo "DuckDNS Token:"
read -s DUCKDNSTOKEN
echo

echo "Nextcloud DB Root Password:"
read -s NCDBROOT
echo

echo "Nextcloud DB User Password:"
read -s NCDBUSER
echo

echo "Timezone (e.g. America/Denver):"
read TZ

PUID=1000
PGID=1000
###############################

COMMON_ENV="DOMAINNAME=$DOMAINNAME
DOCKERPATH=$DOCKERPATH
PROCESSPATH=$PROCESSPATH
MEDIAPATH=$MEDIAPATH
PLEXCLAIM=$PLEXCLAIM
PIAUSER=$PIAUSER
PIAPASS=$PIAPASS
LOCALNET=$LOCALNET
DUCKDNSTOKEN=$DUCKDNSTOKEN
TZ=$TZ
PUID=$PUID
PGID=$PGID"

printf '%s\nNCDBROOT=%s\nNCDBUSER=%s\n' "$COMMON_ENV" "$NCDBROOT" "$NCDBUSER" > ./frontend/.env
printf '%s\n' "$COMMON_ENV" > ./backend/.env
printf '%s\n' "$COMMON_ENV" > ./infrastructure/.env

##########   Docker ###########
bash ./docker.sh
###############################

########  Create Docker Networks  ########
sudo docker network inspect internal >/dev/null 2>&1 || \
    sudo docker network create -d bridge --subnet=172.19.0.0/24 internal
sudo docker network inspect external >/dev/null 2>&1 || \
    sudo docker network create -d bridge --subnet=172.20.0.0/24 external
##########################################

#########  Install Components  ###########
sudo docker compose -f ./infrastructure/docker-compose.yaml up -d
sudo docker compose -f ./backend/docker-compose.yaml up -d
sudo docker compose -f ./frontend/docker-compose.yaml up -d
##########################################

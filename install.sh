#!/bin/bash

set -e

# Remove .env files on exit (success or failure)
cleanup() {
    rm -f ./frontend/.env ./backend/.env ./infrastructure/.env
}
trap cleanup EXIT

# ─────────────────────────────────────────────
#  Service selection menu
# ─────────────────────────────────────────────
SERVICES=(portainer wud netdata duckdns uptime-kuma cloudflared speedtest nzbget transmission prowlarr sonarr radarr tdarr plex overseerr nextcloud ocis)

LABELS=(
    "Portainer         Docker management UI"
    "WUD               Container update notifications"
    "Netdata           System monitoring"
    "DuckDNS           Dynamic DNS"
    "Uptime Kuma       Uptime monitoring"
    "Cloudflared       Cloudflare Tunnel (needs token)"
    "Speedtest         Network speed test"
    "NZBGet            Usenet downloader"
    "Transmission+VPN  Torrent downloader (needs PIA)"
    "Prowlarr          Indexer manager"
    "Sonarr            TV show automation"
    "Radarr            Movie automation"
    "Tdarr             Media transcoding"
    "Plex              Media server"
    "Overseerr         Media requests"
    "Nextcloud         File storage (needs DB creds)"
    "oCIS              ownCloud Infinite Scale (URL)"
)

SVC_GROUPS=(
    "Infrastructure" "Infrastructure" "Infrastructure" "Infrastructure" "Infrastructure" "Infrastructure" "Infrastructure"
    "Downloaders" "Downloaders"
    "*ARR!" "*ARR!" "*ARR!" "*ARR!"
    "Media Server" "Media Server"
    "Private Cloud" "Private Cloud"
)

# Default: all selected except Cloudflared, Nextcloud, and oCIS
SELECTED=(1 1 0 0 0 1 0  1 0  1 1 1 0  1 0  0 0)

show_menu() {
    echo ""
    echo "┌──────────────────────────────────────────────────────────────┐"
    echo "│              Media Server — Select Services                  │"
    echo "├──────────────────────────────────────────────────────────────┤"
    local last_group=""
    for i in "${!SERVICES[@]}"; do
        local group="${SVC_GROUPS[$i]}"
        if [[ "$group" != "$last_group" ]]; then
            printf "│                                                              │\n"
            printf "│  ── %-55s  │\n" "$group"
            last_group="$group"
        fi
        local mark="[ ]"
        [[ "${SELECTED[$i]}" == "1" ]] && mark="[x]"
        printf "│  %2d) %s  %-50s │\n" "$((i+1))" "$mark" "${LABELS[$i]}"
    done
    echo "│                                                              │"
    echo "└──────────────────────────────────────────────────────────────┘"
    echo ""
    echo "  Enter number(s) to toggle (e.g. '3' or '1 4 7')"
    echo "  'a' = select all  |  'n' = deselect all  |  'done' = confirm"
}

while true; do
    show_menu
    read -rp "  > " input
    case "$input" in
        done) break ;;
        a) SELECTED=(1 1 1 1 1 1 1  1 1  1 1 1 1 1  1 1  1 1) ;;
        n) SELECTED=(0 0 0 0 0 0 0  0 0  0 0 0 0 0  0 0  0 0) ;;
        *)
            for num in $input; do
                if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#SERVICES[@]} )); then
                    idx=$((num - 1))
                    [[ "${SELECTED[$idx]}" == "1" ]] && SELECTED[$idx]=0 || SELECTED[$idx]=1
                fi
            done
            ;;
    esac
done

# Returns 0 (true) if the named service is selected
is_selected() {
    for i in "${!SERVICES[@]}"; do
        if [[ "${SERVICES[$i]}" == "$1" && "${SELECTED[$i]}" == "1" ]]; then
            return 0
        fi
    done
    return 1
}

# Builds --profile args for given service names
profile_args() {
    local args=""
    for svc in "$@"; do
        is_selected "$svc" && args="$args --profile $svc"
    done
    echo "$args"
}

# ─────────────────────────────────────────────
#  Collect credentials (only what's needed)
# ─────────────────────────────────────────────
echo ""
echo "── Required Settings ──"

echo "Domain name:"
read -r DOMAINNAME

echo "Path for Docker data (e.g. /mnt/docker):"
read -r DOCKERPATH
sudo mkdir -p "$DOCKERPATH"

echo "Path for temp processing (e.g. /mnt/processing):"
read -r PROCESSPATH
sudo mkdir -p "$PROCESSPATH"

echo "Path for media (e.g. /mnt/media):"
read -r MEDIAPATH
sudo mkdir -p "$MEDIAPATH"

echo "Timezone (e.g. America/Denver):"
read -r TZ

PUID=1000
PGID=1000

if is_selected plex; then
    echo "Plex claim token (from plex.tv/claim):"
    read -r PLEXCLAIM
fi

if is_selected transmission; then
    echo "PIA VPN Username:"
    read -r PIAUSER
    echo "PIA VPN Password:"
    read -rs PIAPASS
    echo
    echo "Local network in CIDR notation (e.g. 192.168.1.0/24):"
    read -r LOCALNET
fi

if is_selected duckdns; then
    echo "DuckDNS token:"
    read -rs DUCKDNSTOKEN
    echo
fi

if is_selected cloudflared; then
    echo "Cloudflare Tunnel connection token:"
    read -rs CF_TUNNEL_TOKEN
    echo
fi

if is_selected nextcloud; then
    echo "Nextcloud DB root password:"
    read -rs NCDBROOT
    echo
    echo "Nextcloud DB user password:"
    read -rs NCDBUSER
    echo
fi

if is_selected ocis; then
    echo "oCIS URL (e.g. https://files.yourdomain.com or https://localhost:9200):"
    read -r OCIS_URL
fi

# ─────────────────────────────────────────────
#  Write .env files
# ─────────────────────────────────────────────
COMMON_ENV="DOMAINNAME=${DOMAINNAME}
DOCKERPATH=${DOCKERPATH}
PROCESSPATH=${PROCESSPATH}
MEDIAPATH=${MEDIAPATH}
PLEXCLAIM=${PLEXCLAIM:-}
PIAUSER=${PIAUSER:-}
PIAPASS=${PIAPASS:-}
LOCALNET=${LOCALNET:-}
DUCKDNSTOKEN=${DUCKDNSTOKEN:-}
CF_TUNNEL_TOKEN=${CF_TUNNEL_TOKEN:-}
OCIS_URL=${OCIS_URL:-}
TZ=${TZ}
PUID=${PUID}
PGID=${PGID}"

printf '%s\nNCDBROOT=%s\nNCDBUSER=%s\n' "$COMMON_ENV" "${NCDBROOT:-}" "${NCDBUSER:-}" > ./frontend/.env
printf '%s\n' "$COMMON_ENV" > ./backend/.env
printf '%s\n' "$COMMON_ENV" > ./infrastructure/.env

# ─────────────────────────────────────────────
#  Install Docker
# ─────────────────────────────────────────────
bash ./docker.sh

# ─────────────────────────────────────────────
#  Create Docker networks (idempotent)
# ─────────────────────────────────────────────
sudo docker network inspect internal >/dev/null 2>&1 || \
    sudo docker network create -d bridge --subnet=172.19.0.0/24 internal
sudo docker network inspect external >/dev/null 2>&1 || \
    sudo docker network create -d bridge --subnet=172.20.0.0/24 external

# ─────────────────────────────────────────────
#  Deploy selected services
# ─────────────────────────────────────────────
INFRA_ARGS=$(profile_args portainer wud netdata duckdns uptime-kuma cloudflared speedtest)
BACKEND_ARGS=$(profile_args nzbget transmission prowlarr sonarr radarr tdarr)
FRONTEND_ARGS=$(profile_args plex overseerr)
NEXTCLOUD_ARGS=$(profile_args nextcloud)
OCIS_ARGS=$(profile_args ocis)

[[ -n "$INFRA_ARGS" ]]     && sudo docker compose -f ./infrastructure/docker-compose.yaml $INFRA_ARGS up -d
[[ -n "$BACKEND_ARGS" ]]   && sudo docker compose -f ./backend/docker-compose.yaml $BACKEND_ARGS up -d
[[ -n "$FRONTEND_ARGS" ]]  && sudo docker compose -f ./frontend/docker-compose.yaml $FRONTEND_ARGS up -d
[[ -n "$NEXTCLOUD_ARGS" ]] && sudo docker compose -f ./frontend/nextcloud.yaml $NEXTCLOUD_ARGS up -d
[[ -n "$OCIS_ARGS" ]]      && sudo docker compose -f ./frontend/ocis.yaml $OCIS_ARGS up -d

LOCAL_IP=$(hostname -I | awk '{print $1}')

echo ""
echo "┌──────────────────────────────────────────────────────────────┐"
echo "│                  Installation Complete!                      │"
echo "│                  Installed Services                          │"
echo "├──────────────────────────────────────────────────────────────┤"

print_url() {
    local label="$1"
    local url="$2"
    printf "│  %-20s %s\n" "$label" "$url"
}

is_selected portainer    && print_url "Portainer"      "http://${LOCAL_IP}:9000"
is_selected wud          && print_url "WUD"            "http://${LOCAL_IP}:3000"
is_selected netdata      && print_url "Netdata"        "http://${LOCAL_IP}:19999"
is_selected uptime-kuma  && print_url "Uptime Kuma"    "http://${LOCAL_IP}:3001"
is_selected speedtest    && print_url "Speedtest"      "http://${LOCAL_IP}:8223"
is_selected nzbget       && print_url "NZBGet"         "http://${LOCAL_IP}:6789"
is_selected transmission && print_url "Transmission"   "http://${LOCAL_IP}:9091"
is_selected prowlarr     && print_url "Prowlarr"       "http://${LOCAL_IP}:9696"
is_selected sonarr       && print_url "Sonarr"         "http://${LOCAL_IP}:8989"
is_selected radarr       && print_url "Radarr"         "http://${LOCAL_IP}:7878"
is_selected tdarr        && print_url "Tdarr"          "http://${LOCAL_IP}:8265"
is_selected plex         && print_url "Plex"           "http://${LOCAL_IP}:32400/web"
is_selected overseerr    && print_url "Overseerr"      "http://${LOCAL_IP}:5055"
is_selected nextcloud    && print_url "Nextcloud"      "http://${LOCAL_IP}:8087"
is_selected ocis         && print_url "oCIS"           "${OCIS_URL}"
is_selected duckdns      && print_url "DuckDNS"        "(no UI — managing ${DOMAINNAME}.duckdns.org)"
is_selected cloudflared  && print_url "Cloudflared"    "(no UI — tunnel active)"

echo "└──────────────────────────────────────────────────────────────┘"
echo ""

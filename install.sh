#!/bin/bash

set -e

# ─────────────────────────────────────────────
#  Saved config (paths and domain name)
# ─────────────────────────────────────────────
CONFIG_FILE="${HOME}/.mediaserver3"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

# Prompt with a saved/default value — press Enter to accept, or type to override
ask() {
    local prompt="$1" varname="$2" fallback="${3:-}" current="${!2}"
    local effective="${current:-$fallback}"
    if [[ -n "$effective" ]]; then
        read -r -p "$prompt [$effective]: " input
        if [[ -n "$input" ]]; then
            printf -v "$varname" '%s' "$input"
        else
            printf -v "$varname" '%s' "$effective"
        fi
    else
        read -r -p "$prompt: " "$varname"
    fi
}

make_dir() {
    sudo mkdir -p "$1"
    sudo chown "${PUID}:${PGID}" "$1"
}

save_config() {
    cat > "$CONFIG_FILE" <<EOF
DOCKERPATH="${DOCKERPATH}"
TZ="${TZ}"
DOMAINNAME="${DOMAINNAME:-}"
PROCESSPATH="${PROCESSPATH:-}"
MEDIAPATH="${MEDIAPATH:-}"
GLUETUN_VPN_TYPE="${GLUETUN_VPN_TYPE:-wireguard}"
EOF
}

# Remove .env files on exit (success or failure)
cleanup() {
    rm -f ./frontend/.env ./backend/.env ./infrastructure/.env
}
trap cleanup EXIT

# ─────────────────────────────────────────────
#  Service selection menu
# ─────────────────────────────────────────────
SERVICES=(portainer wud netdata duckdns uptime-kuma cloudflared speedtest nzbget qbittorrentvpn prowlarr sonarr radarr tdarr plex seerr nextcloud ocis)

LABELS=(
    "Portainer         Docker management UI"
    "WUD               Container update notifications"
    "Netdata           System monitoring"
    "DuckDNS           Dynamic DNS"
    "Uptime Kuma       Uptime monitoring"
    "Cloudflared       Cloudflare Tunnel (needs token)"
    "Speedtest         Network speed test"
    "NZBGet            Usenet downloader"
    "qBittorrent+VPN   Torrent client (any VPN provider)"
    "Prowlarr          Indexer manager"
    "Sonarr            TV show automation"
    "Radarr            Movie automation"
    "Tdarr             Media transcoding"
    "Plex              Media server"
    "Seerr             Media requests"
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
    echo "  'a' = select all  |  'n' = deselect all  |  'c' = clear saved config  |  'go' = confirm"
}

while true; do
    show_menu
    read -rp "  > " input
    case "$input" in
        go) break ;;
        a) SELECTED=(1 1 1 1 1 1 1  1 1  1 1 1 1  1 1  1 1) ;;
        n) SELECTED=(0 0 0 0 0 0 0  0 0  0 0 0 0  0 0  0 0) ;;
        c) rm -f "$CONFIG_FILE" && echo "  Saved config cleared." ;;
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
PUID=$(id -u)
PGID=$(id -g)

echo ""
echo "── Required Settings ──"

ask "Path for Docker data" DOCKERPATH "/opt/docker"
make_dir "$DOCKERPATH"

ask "Timezone" TZ "America/Denver"

if is_selected duckdns || is_selected speedtest; then
    ask "Domain name" DOMAINNAME
fi

if is_selected nzbget || is_selected sonarr || is_selected radarr || is_selected tdarr || is_selected qbittorrentvpn; then
    ask "Path for temp processing" PROCESSPATH "/opt/processing"
    make_dir "$PROCESSPATH"
fi

if is_selected nzbget || is_selected sonarr || is_selected radarr || is_selected tdarr || is_selected plex || is_selected qbittorrentvpn; then
    ask "Path for media" MEDIAPATH "/mnt/media"
    make_dir "$MEDIAPATH"
fi

save_config

if is_selected plex; then
    echo "Plex claim token (from plex.tv/claim):"
    read -r PLEXCLAIM
fi


if is_selected duckdns; then
    echo "DuckDNS token:"
    read -rs DUCKDNSTOKEN
    echo
fi

if is_selected qbittorrentvpn; then
    _detected_subnet=$(ip route | awk '/proto kernel/ && /src/ {split($1,a,"."); printf "%s.%s.%s.0/%s\n", a[1],a[2],a[3], substr($1,index($1,"/")+1)}' | head -1)
    ask "Local subnet for qBittorrent auth bypass (CIDR)" QBIT_SUBNET "${_detected_subnet}"
    ask "VPN type for qBittorrent+VPN (wireguard/openvpn)" GLUETUN_VPN_TYPE "wireguard"
    if [[ "$GLUETUN_VPN_TYPE" == "wireguard" ]]; then
        make_dir "${DOCKERPATH}/gluetun/wireguard"
    else
        make_dir "${DOCKERPATH}/gluetun"
        echo "OpenVPN username:"
        read -r OPENVPN_USER
        echo "OpenVPN password:"
        read -rs OPENVPN_PASSWORD
        echo
        echo "Paste your OpenVPN config file contents, then press Ctrl+D on a new line:"
        cat > "${DOCKERPATH}/gluetun/custom.conf"
        echo "Config written to ${DOCKERPATH}/gluetun/custom.conf"
    fi
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
QBIT_SUBNET=${QBIT_SUBNET:-}
DUCKDNSTOKEN=${DUCKDNSTOKEN:-}
CF_TUNNEL_TOKEN=${CF_TUNNEL_TOKEN:-}
GLUETUN_VPN_TYPE=${GLUETUN_VPN_TYPE:-wireguard}
OPENVPN_USER=${OPENVPN_USER:-}
OPENVPN_PASSWORD=${OPENVPN_PASSWORD:-}
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
#  Pre-configure services
# ─────────────────────────────────────────────
if is_selected sonarr && [[ ! -f "${DOCKERPATH}/sonarr/config.xml" ]]; then
    make_dir "${DOCKERPATH}/sonarr"
    SONARR_API_KEY=$(tr -dc 'a-f0-9' < /dev/urandom | head -c 32)
    sudo tee "${DOCKERPATH}/sonarr/config.xml" > /dev/null <<EOF
<Config>
  <BindAddress>*</BindAddress>
  <Port>8989</Port>
  <SslPort>9898</SslPort>
  <EnableSsl>False</EnableSsl>
  <LaunchBrowser>True</LaunchBrowser>
  <ApiKey>${SONARR_API_KEY}</ApiKey>
  <AuthenticationMethod>External</AuthenticationMethod>
  <Branch>main</Branch>
  <LogLevel>info</LogLevel>
  <UrlBase></UrlBase>
  <UpdateMechanism>Docker</UpdateMechanism>
  <AnalyticsEnabled>True</AnalyticsEnabled>
  <InstanceName>Sonarr</InstanceName>
</Config>
EOF
    sudo chown "${PUID}:${PGID}" "${DOCKERPATH}/sonarr/config.xml"
fi

if is_selected radarr && [[ ! -f "${DOCKERPATH}/radarr/config.xml" ]]; then
    make_dir "${DOCKERPATH}/radarr"
    RADARR_API_KEY=$(tr -dc 'a-f0-9' < /dev/urandom | head -c 32)
    sudo tee "${DOCKERPATH}/radarr/config.xml" > /dev/null <<EOF
<Config>
  <BindAddress>*</BindAddress>
  <Port>7878</Port>
  <SslPort>7879</SslPort>
  <EnableSsl>False</EnableSsl>
  <LaunchBrowser>True</LaunchBrowser>
  <ApiKey>${RADARR_API_KEY}</ApiKey>
  <AuthenticationMethod>External</AuthenticationMethod>
  <Branch>master</Branch>
  <LogLevel>info</LogLevel>
  <UrlBase></UrlBase>
  <UpdateMechanism>Docker</UpdateMechanism>
  <AnalyticsEnabled>True</AnalyticsEnabled>
  <InstanceName>Radarr</InstanceName>
</Config>
EOF
    sudo chown "${PUID}:${PGID}" "${DOCKERPATH}/radarr/config.xml"
fi

if is_selected prowlarr && [[ ! -f "${DOCKERPATH}/prowlarr/config.xml" ]]; then
    make_dir "${DOCKERPATH}/prowlarr"
    PROWLARR_API_KEY=$(tr -dc 'a-f0-9' < /dev/urandom | head -c 32)
    sudo tee "${DOCKERPATH}/prowlarr/config.xml" > /dev/null <<EOF
<Config>
  <BindAddress>*</BindAddress>
  <Port>9696</Port>
  <SslPort>6969</SslPort>
  <EnableSsl>False</EnableSsl>
  <LaunchBrowser>True</LaunchBrowser>
  <ApiKey>${PROWLARR_API_KEY}</ApiKey>
  <AuthenticationMethod>External</AuthenticationMethod>
  <Branch>master</Branch>
  <LogLevel>info</LogLevel>
  <UrlBase></UrlBase>
  <UpdateMechanism>Docker</UpdateMechanism>
  <AnalyticsEnabled>True</AnalyticsEnabled>
  <InstanceName>Prowlarr</InstanceName>
</Config>
EOF
    sudo chown "${PUID}:${PGID}" "${DOCKERPATH}/prowlarr/config.xml"
fi

if is_selected qbittorrentvpn && [[ ! -f "${DOCKERPATH}/qbittorrent/qBittorrent/qBittorrent.conf" ]]; then
    make_dir "${DOCKERPATH}/qbittorrent/qBittorrent"
    sudo tee "${DOCKERPATH}/qbittorrent/qBittorrent/qBittorrent.conf" > /dev/null <<EOF
[BitTorrent]
Session\DefaultSavePath=/downloads

[Preferences]
WebUI\AuthSubnetWhitelist=${QBIT_SUBNET}
WebUI\AuthSubnetWhitelistEnabled=true
EOF
    sudo chown -R "${PUID}:${PGID}" "${DOCKERPATH}/qbittorrent"
fi

# ─────────────────────────────────────────────
#  Deploy selected services
# ─────────────────────────────────────────────
INFRA_ARGS=$(profile_args portainer wud netdata duckdns uptime-kuma cloudflared speedtest)
BACKEND_ARGS=$(profile_args nzbget qbittorrentvpn prowlarr sonarr radarr tdarr)
FRONTEND_ARGS=$(profile_args plex seerr)
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
is_selected nzbget       && print_url "NZBGet"         "http://${LOCAL_IP}:6789  (user: nzbget / pass: tegbzn6789)"
if is_selected qbittorrentvpn; then
    if [[ "${GLUETUN_VPN_TYPE}" == "wireguard" ]]; then
        print_url "qBittorrent+VPN" "http://${LOCAL_IP}:8080  (place config at ${DOCKERPATH}/gluetun/wireguard/wg0.conf)"
    else
        print_url "qBittorrent+VPN" "http://${LOCAL_IP}:8080  (place config at ${DOCKERPATH}/gluetun/custom.conf)"
    fi
fi
is_selected prowlarr     && print_url "Prowlarr"       "http://${LOCAL_IP}:9696"
is_selected sonarr       && print_url "Sonarr"         "http://${LOCAL_IP}:8989"
is_selected radarr       && print_url "Radarr"         "http://${LOCAL_IP}:7878"
is_selected tdarr        && print_url "Tdarr"          "http://${LOCAL_IP}:8265"
is_selected plex         && print_url "Plex"           "http://${LOCAL_IP}:32400/web"
is_selected seerr        && print_url "Seerr"           "http://${LOCAL_IP}:5055"
is_selected nextcloud    && print_url "Nextcloud"      "http://${LOCAL_IP}:8087"
is_selected ocis         && print_url "oCIS"           "${OCIS_URL}"
is_selected duckdns      && print_url "DuckDNS"        "(no UI — managing ${DOMAINNAME}.duckdns.org)"
is_selected cloudflared  && print_url "Cloudflared"    "(no UI — tunnel active)"

echo "└──────────────────────────────────────────────────────────────┘"
echo ""

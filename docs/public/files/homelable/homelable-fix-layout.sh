#!/usr/bin/env bash
# homelable-fix-layout.sh
# Grows the Proxmox host box and lays out its VMs/LXCs so a large container-mode
# VM box (for example one holding Docker containers) fits beside them.
#
# Needs: curl, jq
#
#   HL_URL=http://<homelable-ip>:3000 HL_USER=admin HL_PASS='...' HOST_IP=<docker-vm-ip> ./homelable-fix-layout.sh          dry run
#   APPLY=1 HL_URL=http://<homelable-ip>:3000 HL_USER=admin HL_PASS='...' HOST_IP=<docker-vm-ip> ./homelable-fix-layout.sh  apply
set -uo pipefail
HL_URL="${HL_URL:?set HL_URL}"; HL_USER="${HL_USER:?set HL_USER}"; HL_PASS="${HL_PASS:?set HL_PASS}"
HOST_IP="${HOST_IP:?set HOST_IP to the IP of the large VM}"; APPLY="${APPLY:-0}"
COLS="${COLS:-3}"; CELL_W=240; CELL_H=100; PAD=20; TOP=60
API="$HL_URL/api/v1"

TOKEN="$(curl -s "$API/auth/login" -H 'Content-Type: application/json' \
  -d "$(jq -n --arg u "$HL_USER" --arg p "$HL_PASS" '{"username":$u,"password":$p}')" | jq -r '.access_token // empty')"
[[ -n "$TOKEN" ]] || { echo "Login failed"; exit 1; }
AUTH=(-H "Authorization: Bearer $TOKEN")
NODES="$(curl -s "$API/nodes" "${AUTH[@]}")"

BIG="$(jq -c --arg ip "$HOST_IP" '[.[] | select(.type=="vm" and ((.ip // "") | split(",") | map(gsub("\\s";"")) | index($ip)))][0] // empty' <<<"$NODES")"
[[ -n "$BIG" ]] || { echo "No VM with IP $HOST_IP"; exit 1; }
BID="$(jq -r .id <<<"$BIG")"; HID="$(jq -r '.parent_id // empty' <<<"$BIG")"
[[ -n "$HID" ]] || { echo "That VM has no parent, nothing to fix"; exit 0; }
BW="$(jq -r '(.width // 960) | floor' <<<"$BIG")"; BH="$(jq -r '(.height // 490) | floor' <<<"$BIG")"
echo "Host box: $(jq -r --arg h "$HID" '.[] | select(.id==$h) | .label' <<<"$NODES") ($HID)"
echo "Big VM:   $(jq -r .label <<<"$BIG") ${BW}x${BH}"

mapfile -t OTHERS < <(jq -r --arg h "$HID" --arg b "$BID" \
  '.[] | select(.parent_id==$h and .id!=$b) | "\(.id)|\(.label)"' <<<"$NODES" | sort -t'|' -k2)
rows=$(( (${#OTHERS[@]} + COLS - 1) / COLS ))
COLX=$(( PAD + BW + 40 ))
HW=$(( COLX + COLS * CELL_W + PAD ))
GRID_H=$(( rows * CELL_H )); (( GRID_H > BH )) && INNER=$GRID_H || INNER=$BH
HH=$(( TOP + INNER + 30 ))
echo "Host box -> ${HW}x${HH}; ${#OTHERS[@]} other guests in $COLS columns"

patch() { # id json label
  if [[ "$APPLY" == "1" ]]; then
    curl -s -o /dev/null -w "  $3: HTTP %{http_code}\n" -X PATCH "$API/nodes/$1" "${AUTH[@]}" -H 'Content-Type: application/json' -d "$2"
  else
    echo "  would patch $3: $2"
  fi
}

patch "$HID" "$(jq -nc --argjson w "$HW" --argjson h "$HH" '{"container_mode":true,"width":$w,"height":$h}')" "host box"
patch "$BID" "$(jq -nc --argjson x "$PAD" --argjson y "$TOP" '{"pos_x":$x,"pos_y":$y}')" "$(jq -r .label <<<"$BIG")"
i=0
for row in "${OTHERS[@]}"; do
  id="${row%%|*}"; name="${row#*|}"
  x=$(( COLX + (i % COLS) * CELL_W )); y=$(( TOP + (i / COLS) * CELL_H ))
  patch "$id" "$(jq -nc --argjson x "$x" --argjson y "$y" '{"pos_x":$x,"pos_y":$y}')" "$name"
  i=$((i + 1))
done
[[ "$APPLY" == "1" ]] || echo "(dry run: set APPLY=1 to apply)"

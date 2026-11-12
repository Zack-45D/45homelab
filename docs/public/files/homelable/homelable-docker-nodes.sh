#!/usr/bin/env bash
# homelable-docker-nodes.sh
# Run on the Docker host VM as a user that can run `docker ps`.
#
# Reads the running containers and creates a Homelable `docker_container` node for
# each one, nested inside that VM's node (container mode). Safe to re-run:
# containers that already have a node under the VM are skipped.
#
# Needs: curl, jq   (apt install -y curl jq)
#
# Usage:
#   HL_URL=http://<homelable-ip>:3000 HOST_IP=<docker-vm-ip> HL_USER=admin HL_PASS='yourpass' ./homelable-docker-nodes.sh          # dry run
#   APPLY=1 HL_URL=http://<homelable-ip>:3000 HOST_IP=<docker-vm-ip> HL_USER=admin HL_PASS='yourpass' ./homelable-docker-nodes.sh  # create nodes
#
# Before APPLY: save your canvas in the browser. After APPLY: reload the page
# (do not click Save on an old, unreloaded tab or it will overwrite the new nodes).

set -uo pipefail

HL_URL="${HL_URL:?set HL_URL, e.g. http://192.168.1.20:3000}"
HL_USER="${HL_USER:?set HL_USER}"
HL_PASS="${HL_PASS:?set HL_PASS}"
HOST_IP="${HOST_IP:?set HOST_IP to the IP of this VM as shown in Homelable}"
APPLY="${APPLY:-0}"
COLS="${COLS:-4}"                      # containers per row inside the VM box
CELL_W=230; CELL_H=100; PAD_X=20; PAD_Y=70

# Helper containers (databases, caches, sidecars) to leave off the canvas.
# Space separated container names, e.g. SKIP="app-postgres app-redis"
SKIP=" ${SKIP:-} "

# Optional notes per container, shown on the node's detail panel. Example:
#   [myapp]="Uses myapp-postgres + myapp-redis"
declare -A NOTES=(
)

API="$HL_URL/api/v1"
command -v jq >/dev/null || { echo "jq is required: apt install -y jq"; exit 1; }

# --- Log in ---
TOKEN="$(curl -s "$API/auth/login" -H 'Content-Type: application/json' \
  -d "$(jq -n --arg u "$HL_USER" --arg p "$HL_PASS" '{"username":$u,"password":$p}')" \
  | jq -r '.access_token // empty')"
[[ -n "$TOKEN" ]] || { echo "Login failed. Check HL_URL / HL_USER / HL_PASS."; exit 1; }
AUTH=(-H "Authorization: Bearer $TOKEN")

# --- Find the VM node for this host ---
NODES="$(curl -s "$API/nodes" "${AUTH[@]}")"
PARENT="$(jq -c --arg ip "$HOST_IP" '
  [ .[] | select((.ip // "") | split(",") | map(gsub("\\s";"")) | index($ip)) ]
  | (map(select(.type=="vm")) + .) | .[0] // empty' <<<"$NODES")"
[[ -n "$PARENT" ]] || { echo "No node with IP $HOST_IP found. Import the VM from Proxmox first."; exit 1; }

PID="$(jq -r .id <<<"$PARENT")"
PLABEL="$(jq -r .label <<<"$PARENT")"
DESIGN="$(jq -r '.design_id // empty' <<<"$PARENT")"
echo "Parent node: $PLABEL ($PID, type $(jq -r .type <<<"$PARENT"))"

EXISTING="$(jq -r --arg pid "$PID" '.[] | select(.parent_id==$pid) | .label' <<<"$NODES")"

# --- Collect containers ---
mapfile -t ROWS < <(docker ps --format '{{.Names}}|{{.Image}}|{{.Ports}}' | sort)

TODO=()
for row in "${ROWS[@]}"; do
  name="${row%%|*}"
  [[ "$SKIP" == *" $name "* ]] && { echo "  skip (helper): $name"; continue; }
  grep -qxF "$name" <<<"$EXISTING" && { echo "  skip (exists): $name"; continue; }
  TODO+=("$row")
done

# Count every child (existing + new) to size the VM box
total=$(( $(grep -c . <<<"$EXISTING") + ${#TODO[@]} ))
rows=$(( (total + COLS - 1) / COLS ))
WIDTH=$(( PAD_X * 2 + COLS * CELL_W ))
HEIGHT=$(( PAD_Y + rows * CELL_H + 20 ))
start=$(grep -c . <<<"$EXISTING")

echo "Will create ${#TODO[@]} node(s); VM box ${WIDTH}x${HEIGHT}"
[[ "$APPLY" == "1" ]] || echo "(dry run: set APPLY=1 to create)"

# --- Turn on container mode on the VM node ---
if [[ "$APPLY" == "1" && ${#TODO[@]} -gt 0 ]]; then
  curl -s -o /dev/null -w "  container mode on $PLABEL: HTTP %{http_code}\n" -X PATCH "$API/nodes/$PID" "${AUTH[@]}" \
    -H 'Content-Type: application/json' \
    -d "$(jq -n --argjson w "$WIDTH" --argjson h "$HEIGHT" '{"container_mode":true,"width":$w,"height":$h}')"
fi

# --- Create the container nodes ---
i=$start
for row in "${TODO[@]}"; do
  IFS='|' read -r name image ports <<<"$row"
  pub="$(grep -oE ':[0-9]+(-[0-9]+)?->' <<<"$ports" | sed -E 's/^:(.*)->$/\1/' | sort -un | paste -sd, -)"
  x=$(( PAD_X + (i % COLS) * CELL_W ))
  y=$(( PAD_Y + (i / COLS) * CELL_H ))
  note="${NOTES[$name]:-}"

  body="$(jq -n \
    --arg lbl "$name" --arg pid "$PID" --arg design "$DESIGN" \
    --arg image "$image" --arg pub "${pub:-none published}" --arg note "$note" \
    --argjson x "$x" --argjson y "$y" '
    {
      "type": "docker_container", "label": $lbl, "parent_id": $pid,
      "pos_x": $x, "pos_y": $y,
      "notes": (if $note == "" then null else $note end),
      "properties": [
        {"key":"Ports", "value":$pub,   "icon":null, "visible":true},
        {"key":"Image", "value":$image, "icon":null, "visible":false}
      ]
    } + (if $design == "" then {} else {"design_id":$design} end)')"

  if [[ "$APPLY" == "1" ]]; then
    code="$(curl -s -o /dev/null -w '%{http_code}' "$API/nodes" "${AUTH[@]}" \
      -H 'Content-Type: application/json' -d "$body")"
    echo "  create $name (ports: ${pub:-none}): HTTP $code"
  else
    echo "  would create $name (ports: ${pub:-none}) at $x,$y"
  fi
  i=$((i + 1))
done

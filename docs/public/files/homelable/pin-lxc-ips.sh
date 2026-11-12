#!/usr/bin/env bash
# pin-lxc-ips.sh
# Run on the Proxmox host as root.
# For each running LXC on ip=dhcp, reads its current IPv4 + gateway and
# rewrites net0 with that same address as static. Other net0 options are kept.
#   ./pin-lxc-ips.sh          dry run
#   APPLY=1 ./pin-lxc-ips.sh  apply

set -uo pipefail
APPLY="${APPLY:-0}"

printf "%-6s %-18s %-20s %-15s %s\n" "CTID" "HOSTNAME" "CURRENT_IP" "GATEWAY" "RESULT"

for ctid in $(pct list | awk 'NR>1 {print $1}'); do
    cfg="$(pct config "$ctid")"
    net0="$(awk -F': ' '/^net0:/ {print $2}' <<<"$cfg")"
    host="$(awk -F': ' '/^hostname:/ {print $2}' <<<"$cfg")"

    [[ "$net0" == *ip=dhcp* ]] || continue

    if [[ "$(pct status "$ctid" | awk '{print $2}')" != "running" ]]; then
        printf "%-6s %-18s %-20s %-15s %s\n" "$ctid" "${host:0:18}" "-" "-" "skipped (stopped)"
        continue
    fi

    cidr="$(pct exec "$ctid" -- ip -4 -o addr show dev eth0 2>/dev/null | awk '{print $4; exit}')"
    gw="$(pct exec "$ctid" -- ip -4 route show default 2>/dev/null | awk '{print $3; exit}')"

    if [[ -z "$cidr" || -z "$gw" ]]; then
        printf "%-6s %-18s %-20s %-15s %s\n" "$ctid" "${host:0:18}" "${cidr:--}" "${gw:--}" "skipped (no IP/gw found)"
        continue
    fi

    # Replace only the IPv4 ip=dhcp, leave ip6= alone
    new_net0="$(sed -E "s/(^|,)ip=dhcp(,|$)/\1ip=${cidr//\//\\/},gw=${gw}\2/" <<<"$net0")"

    if [[ "$APPLY" == "1" ]]; then
        if pct set "$ctid" --net0 "$new_net0"; then
            result="pinned"
        else
            result="FAILED"
        fi
    else
        result="would set: $new_net0"
    fi

    printf "%-6s %-18s %-20s %-15s %s\n" "$ctid" "${host:0:18}" "$cidr" "$gw" "$result"
done

#!/usr/bin/env bash
# enable-qga.sh
# Run on the Proxmox host as root.
#
# - Turns on the QEMU guest agent option for every VM that doesn't have it.
# - Optionally cold-restarts changed VMs so the agent device appears.
# - Checks which running VMs have a responding agent.
# - Lists LXCs whose net0 has no static IP (Homelable can't read their IP).
#
# Usage:
#   ./enable-qga.sh               # dry run, shows what would change
#   APPLY=1 ./enable-qga.sh       # enable the agent option on VMs
#   APPLY=1 RESTART=1 ./enable-qga.sh
#                                    # also shutdown + start changed running VMs

set -uo pipefail

APPLY="${APPLY:-0}"
RESTART="${RESTART:-0}"
SHUTDOWN_TIMEOUT="${SHUTDOWN_TIMEOUT:-180}"

changed=()

echo "=== VMs ==="
printf "%-6s %-25s %-9s %-10s %s\n" "VMID" "NAME" "STATUS" "AGENT_OPT" "AGENT_PING"

for vmid in $(qm list | awk 'NR>1 {print $1}'); do
    cfg="$(qm config "$vmid")"
    name="$(awk -F': ' '/^name:/ {print $2}' <<<"$cfg")"
    status="$(qm status "$vmid" | awk '{print $2}')"
    agent="$(awk -F': ' '/^agent:/ {print $2}' <<<"$cfg")"

    if [[ "$agent" == 1* || "$agent" == *enabled=1* ]]; then
        agent_opt="on"
    else
        agent_opt="off"
        if [[ "$APPLY" == "1" ]]; then
            if qm set "$vmid" --agent enabled=1 >/dev/null; then
                agent_opt="set"
                changed+=("$vmid")
            else
                agent_opt="FAILED"
            fi
        else
            agent_opt="off(dry)"
        fi
    fi

    ping="-"
    if [[ "$status" == "running" && "$agent_opt" == "on" ]]; then
        if qm agent "$vmid" ping >/dev/null 2>&1; then
            ping="ok"
        else
            ping="no reply (package not installed/running?)"
        fi
    fi

    printf "%-6s %-25s %-9s %-10s %s\n" "$vmid" "${name:0:25}" "$status" "$agent_opt" "$ping"
done

if [[ "$APPLY" == "1" && "$RESTART" == "1" && ${#changed[@]} -gt 0 ]]; then
    echo
    echo "=== Cold restarting changed running VMs ==="
    for vmid in "${changed[@]}"; do
        if [[ "$(qm status "$vmid" | awk '{print $2}')" == "running" ]]; then
            echo "VM $vmid: shutting down (timeout ${SHUTDOWN_TIMEOUT}s)..."
            if qm shutdown "$vmid" --timeout "$SHUTDOWN_TIMEOUT"; then
                qm start "$vmid" && echo "VM $vmid: started"
            else
                echo "VM $vmid: clean shutdown failed, left as is. Handle manually."
            fi
        fi
    done
elif [[ ${#changed[@]} -gt 0 ]]; then
    echo
    echo "Agent option set on: ${changed[*]}"
    echo "These need a full shutdown + start (not a reboot from inside) to take effect."
fi

echo
echo "=== LXCs without a static IP in net0 ==="
printf "%-6s %-25s %s\n" "CTID" "HOSTNAME" "NET0"
found=0
for ctid in $(pct list | awk 'NR>1 {print $1}'); do
    cfg="$(pct config "$ctid")"
    host="$(awk -F': ' '/^hostname:/ {print $2}' <<<"$cfg")"
    net0="$(awk -F': ' '/^net0:/ {print $2}' <<<"$cfg")"
    if [[ -z "$net0" || "$net0" == *ip=dhcp* || "$net0" != *ip=* ]]; then
        printf "%-6s %-25s %s\n" "$ctid" "${host:0:25}" "${net0:-<none>}"
        found=1
    fi
done
[[ "$found" == "0" ]] && echo "All LXCs have a static IP in net0."

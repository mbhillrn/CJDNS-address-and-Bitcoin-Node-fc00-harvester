#!/usr/bin/env bash
# CJDNS Harvester v5 - Onetry Execution Module

# Requires: ui.sh, db.sh, canon_host

# ============================================================================
# Onetry Execution
# ============================================================================
onetry_addresses() {
    # Usage: onetry_addresses address1 address2 address3 ...
    # Dispatches addnode onetry for all provided addresses

    local addresses=("$@")
    local count=${#addresses[@]}

    (( count > 0 )) || {
        status_info "No addresses to try"
        return 0
    }

    print_section "Attempting Connection to $count Addresses"

    # Get snapshot of currently connected peers BEFORE onetry
    local pre_peers="/tmp/cjdh_pre_peers.$$"
    bash -c "$CLI getpeerinfo" 2>/dev/null \
        | jq -r '.[] | select(.network=="cjdns") | .addr' 2>/dev/null \
        | while IFS= read -r raw; do
            canon_host "$(cjdns_host_from_maybe_bracketed "$raw")"
        done | sort -u > "$pre_peers"

    # Dispatch onetry for each address
    local dispatched=0
    for addr in "${addresses[@]}"; do
        addr="$(canon_host "$addr")"
        [[ -n "$addr" ]] || continue

        printf "  ${C_MUTED}Trying:${C_RESET} %s ... " "$addr"

        if bash -c "$CLI addnode \"[$addr]\" onetry" >/dev/null 2>&1; then
            printf "${C_SUCCESS}dispatched${C_RESET}\n"
            dispatched=$((dispatched + 1))
        else
            printf "${C_ERROR}failed${C_RESET}\n"
        fi
    done

    # Wait for connections to settle
    if (( dispatched > 0 )); then
        echo
        show_progress "Waiting 5 seconds for connections to settle"
        sleep 5
        show_progress_done
    fi

    # Get snapshot of currently connected peers AFTER onetry
    local post_peers="/tmp/cjdh_post_peers.$$"
    bash -c "$CLI getpeerinfo" 2>/dev/null \
        | jq -r '.[] | select(.network=="cjdns") | .addr' 2>/dev/null \
        | while IFS= read -r raw; do
            canon_host "$(cjdns_host_from_maybe_bracketed "$raw")"
        done | sort -u > "$post_peers"

    # Find new connections (diff post - pre)
    local new_connections="/tmp/cjdh_new_conn.$$"
    comm -13 "$pre_peers" "$post_peers" > "$new_connections" 2>/dev/null

    local connected_count
    connected_count="$(wc -l < "$new_connections" 2>/dev/null || echo 0)"

    # Report results
    echo
    print_divider
    printf "${C_BOLD}Onetry Results:${C_RESET}\n"
    printf "  Dispatched:  %s\n" "$dispatched"
    if (( connected_count > 0 )); then
        printf "  ${C_SUCCESS}${C_BOLD}Connected:   %s${C_RESET}\n" "$connected_count"

        echo
        printf "  ${C_SUCCESS}New connections:${C_RESET}\n"
        while IFS= read -r addr; do
            [[ -n "$addr" ]] || continue
            printf "    ${C_SUCCESS}✓${C_RESET} %s\n" "$addr"

            # Auto-confirm connected addresses
            db_upsert_confirmed "$addr"
            db_upsert_master "$addr" "onetry_connected"
        done < "$new_connections"
    else
        printf "  ${C_MUTED}Connected:   0${C_RESET}\n"
    fi
    print_divider

    # Cleanup
    rm -f "$pre_peers" "$post_peers" "$new_connections"

    return 0
}

# ============================================================================
# Batch Onetry from Database Table
# ============================================================================
onetry_all_master() {
    print_box "ONETRY: ALL MASTER LIST"

    local master_count
    master_count="$(db_count_master)"

    if (( master_count == 0 )); then
        status_warn "Master list is empty, nothing to try"
        return 0
    fi

    status_info "Master list contains $master_count addresses"
    echo

    # Get all addresses from master table
    local addresses
    mapfile -t addresses < <(db_get_all_master)

    onetry_addresses "${addresses[@]}"
}

onetry_all_confirmed() {
    print_box "ONETRY: ALL CONFIRMED LIST"

    local confirmed_count
    confirmed_count="$(db_count_confirmed)"

    if (( confirmed_count == 0 )); then
        status_warn "Confirmed list is empty, nothing to try"
        return 0
    fi

    status_info "Confirmed list contains $confirmed_count addresses (known Bitcoin nodes)"
    echo

    # Get all addresses from confirmed table
    local addresses
    mapfile -t addresses < <(db_get_all_confirmed)

    onetry_addresses "${addresses[@]}"
}

# ============================================================================
# Onetry only NEW addresses (for harvester mode)
# ============================================================================
onetry_new_addresses() {
    # Get all master addresses and check which ones have never been confirmed
    local all_master new_addresses=()

    while IFS= read -r addr; do
        [[ -n "$addr" ]] || continue

        # Check if NOT in confirmed table
        local in_confirmed
        in_confirmed="$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM confirmed WHERE host='$addr';" 2>/dev/null || echo "0")"
        if (( in_confirmed == 0 )); then
            new_addresses+=("$addr")
        fi
    done < <(db_get_all_master)

    local count=${#new_addresses[@]}

    if (( count == 0 )); then
        status_info "No new addresses to try (all already tested)"
        return 0
    fi

    status_info "Found $count new addresses to test"
    echo

    onetry_addresses "${new_addresses[@]}"
}

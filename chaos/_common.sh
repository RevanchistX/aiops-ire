#!/usr/bin/env bash
# chaos/_common.sh
# Shared helpers sourced by every chaos script. Not executed directly.

GITHUB_ISSUES_URL="https://github.com/DeniStojanovski/aiops-ire/issues"

# Print a bold section banner
banner() {
    local title="$1"
    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    printf  "║  CHAOS: %-44s║\n" "$title"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""
}

# Return the name of the first Running flask-app pod (or any pod if none Running)
get_pod() {
    local namespace="$1"
    local service="$2"

    local pod
    # Prefer a Running pod; fall back to any pod with the app label
    pod=$(kubectl get pods -n "$namespace" -l "app=${service}" \
            --field-selector=status.phase=Running \
            --no-headers -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

    if [[ -z "$pod" ]]; then
        pod=$(kubectl get pods -n "$namespace" -l "app=${service}" \
                --no-headers -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    fi

    if [[ -z "$pod" ]]; then
        echo "[✗] No pod found with label app=${service} in namespace ${namespace}" >&2
        echo "    Is the flask-app deployed? Run: terraform apply -target=module.apps" >&2
        exit 1
    fi

    echo "$pod"
}

# Print the issues URL at the end of every chaos run
print_watch_url() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Watch for auto-generated GitHub issues at:"
    echo "  ${GITHUB_ISSUES_URL}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

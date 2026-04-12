#!/bin/bash

# Configuration
CONTROL_URL="http://localhost:8080"
GATEWAY_HOST="localhost"
GATEWAY_PORT="5433"
DEFAULT_DB="lake"

# Load ADMIN_API_KEY from .env
if [ -f .env ]; then
    # Export variables from .env, ignoring comments and empty lines
    export $(grep -v '^#' .env | xargs)
else
    echo "Error: .env file not found."
    exit 1
fi

if [ -z "$ADMIN_API_KEY" ]; then
    echo "Error: ADMIN_API_KEY not found in .env"
    exit 1
fi

# Check for prerequisites
if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' is not installed. Please install it to parse JSON responses."
    exit 1
fi

if ! command -v psql &> /dev/null; then
    echo "Error: 'psql' is not installed. Please install the PostgreSQL client."
    exit 1
fi

# 1. Fetch and List Tenants
echo "Fetching available tenants..."
TENANTS_JSON=$(curl -s -f -H "X-Admin-API-Key: $ADMIN_API_KEY" "$CONTROL_URL/api/v1/admin/tenants")

if [ $? -ne 0 ] || [ -z "$TENANTS_JSON" ]; then
    echo "Error: Failed to fetch tenants from $CONTROL_URL. Is the control plane running?"
    exit 1
fi

if ! echo "$TENANTS_JSON" | jq -e 'type == "array"' > /dev/null; then
    echo "Error: Invalid response from control plane."
    echo "$TENANTS_JSON"
    exit 1
fi

# Prepare selection menu
OPTIONS=()
IDS=()
while IFS=$'\t' read -r id org; do
    OPTIONS+=("$org ($id)")
    IDS+=("$id")
done < <(echo "$TENANTS_JSON" | jq -r '.[] | "\(.id)\t\(.org_name)"')

if [ ${#OPTIONS[@]} -eq 0 ]; then
    echo "No tenants found."
    exit 0
fi

echo "------------------------------------------------"
echo "Select a tenant to connect to:"
PS3="Enter number (1-${#OPTIONS[@]}): "
select opt in "${OPTIONS[@]}"; do
    if [ -n "$opt" ]; then
        # REPLY is the index chosen by the user
        SELECTED_ID="${IDS[$((REPLY-1))]}"
        SELECTED_NAME="$opt"
        break
    else
        echo "Invalid choice. Please try again."
    fi
done

echo "------------------------------------------------"
echo "Selected: $SELECTED_NAME"

# 2. Rotate Service Account Credentials
echo "Rotating service account key for $SELECTED_ID..."
ROTATE_JSON=$(curl -s -f -X POST -H "X-Admin-API-Key: $ADMIN_API_KEY" "$CONTROL_URL/api/v1/admin/tenants/$SELECTED_ID/service-account/rotate")

if [ $? -ne 0 ] || [ -z "$ROTATE_JSON" ]; then
    echo "Error: Failed to rotate service account credentials."
    exit 1
fi

SERVICE_ID=$(echo "$ROTATE_JSON" | jq -r '.service_id')
SERVICE_KEY=$(echo "$ROTATE_JSON" | jq -r '.service_api_key')

if [ "$SERVICE_ID" == "null" ] || [ -z "$SERVICE_ID" ]; then
    echo "Error: Service ID not found in rotation response."
    echo "Response: $ROTATE_JSON"
    exit 1
fi

echo "Success: Service account credentials rotated."
echo "Service User ID: $SERVICE_ID"

# 3. Launch psql session
echo "------------------------------------------------"
echo "Launching psql session..."
echo "Connecting to $GATEWAY_HOST:$GATEWAY_PORT/$DEFAULT_DB"
echo "------------------------------------------------"

export PGPASSWORD="$SERVICE_KEY"
psql -h "$GATEWAY_HOST" -p "$GATEWAY_PORT" -U "$SERVICE_ID" -d "$DEFAULT_DB"

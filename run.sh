#!/usr/bin/with-contenv bashio
set -e

SSH_DIR=~/.ssh

ROUTER_USER="$(bashio::config 'sslFromAsusRouter.routerUser')"
ROUTER_IP="$(bashio::config 'sslFromAsusRouter.routerIp')"
ROUTER_PORT="$(bashio::config 'sslFromAsusRouter.routerSshPort')"
RSA_PRIVATE_KEY_PATH="$(bashio::config 'sslFromAsusRouter.rsaPrivateKeyPath')"
KEY_PATH_ON_ROUTER="$(bashio::config 'sslFromAsusRouter.keyFilePathOnRouter')"
CERT_PATH_ON_ROUTER="$(bashio::config 'sslFromAsusRouter.certFilePathOnRouter')"
STATUS_HELPER="$(bashio::config 'sslFromAsusRouter.statusHelper')"

echo "Getting Router Public RSA Key...."
CERT_PATH_ON_ROUTER="$(bashio::config 'sslFromAsusRouter.certFilePathOnRouter')"

bashio::log.info "=== MY FORK AUTOMATION START ==="

# --- MANDATORY FIELDS VALIDATION (Excluding statusHelper) ---
if [ -z "$ROUTER_USER" ] || [ -z "$ROUTER_IP" ] || [ -z "$ROUTER_PORT" ] || \
   [ -z "$RSA_PRIVATE_KEY_PATH" ] || [ -z "$KEY_PATH_ON_ROUTER" ] || [ -z "$CERT_PATH_ON_ROUTER" ]; then
    
    bashio::log.error "-------------------------------------------------------------------"
    bashio::log.error " CRITICAL ERROR: Mandatory configuration options are missing!"
    bashio::log.error " Please ensure all fields except the Status Helper are filled in UI."
    bashio::log.error "-------------------------------------------------------------------"
    
    exec /run/s6/basedir/bin/halt
fi
# ------------------------------------------------------------

echo "Creating ${SSH_DIR}..."
mkdir -p ${SSH_DIR}

echo "Setting id_rsa file..."
cp /homeassistant/"${RSA_PRIVATE_KEY_PATH}" ${SSH_DIR}/id_rsa
chmod 600 ${SSH_DIR}/id_rsa

# We scan the router's key and save it directly to known_hosts (replacing the faulty author's loop)
echo "Scanning router public RSA key and saving to known_hosts..."
ssh-keyscan -p ${ROUTER_PORT} -t rsa ${ROUTER_IP} > ${SSH_DIR}/known_hosts
chmod 644 ${SSH_DIR}/known_hosts

LOCAL_CERT="/ssl/cert.pem"

# Short SSH configuration for better code readability
SSH_CMD="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p ${ROUTER_PORT} -i /homeassistant/${RSA_PRIVATE_KEY_PATH}"

# 1. Check if the local certificate file exists
if [ -f "$LOCAL_CERT" ]; then
    bashio::log.info "Local certificate found. Checking version on the router..."
    
    # Fetch modification time of the local file (in Unix seconds)
    LOCAL_TIME=$(stat -c %Y "$LOCAL_CERT")
    # Convert local timestamp to human-readable format:
    HUMAN_LOCAL_TIME=$(date -d "@$LOCAL_TIME" "+%Y-%m-%d %H:%M:%S")
    bashio::log.info "Local certificate timestamp: $HUMAN_LOCAL_TIME"
    
    # Fetch modification time of the file on the router via SSH
    REMOTE_TIME=$($SSH_CMD ${ROUTER_USER}@${ROUTER_IP} "date -r ${CERT_PATH_ON_ROUTER} +%s")
    
    # Verify if REMOTE_TIME is a valid number before conversion
    if [ -n "$REMOTE_TIME" ] && [ "$REMOTE_TIME" -eq "$REMOTE_TIME" ] 2>/dev/null; then
        HUMAN_REMOTE_TIME=$(date -d "@$REMOTE_TIME" "+%Y-%m-%d %H:%M:%S")
        bashio::log.info "Remote certificate timestamp: $HUMAN_REMOTE_TIME"
    else
        bashio::log.info "Remote certificate timestamp: Raw data invalid or empty"
    fi

    # Fallback validation in case the router fails to return a timestamp
    if [ -z "$REMOTE_TIME" ] || ! [ "$REMOTE_TIME" -eq "$REMOTE_TIME" ] 2>/dev/null; then
        bashio::log.warning "Failed to fetch timestamp from the router. Forcing download for safety."
        REMOTE_TIME=$((LOCAL_TIME + 1))
    fi

    # 2. Compare timestamps
    if [ "$LOCAL_TIME" -ge "$REMOTE_TIME" ]; then
        bashio::log.info "The certificate in Home Assistant is UP TO DATE (same or newer than on the router)."
        bashio::log.info "Copying skipped. Exiting..."
 		exec /run/s6/basedir/bin/halt
    else
        bashio::log.info "Detected a newer certificate on the ASUS router. Starting download..."
    fi
else
    bashio::log.info "No local certificate found in /ssl. Fetching for the first time..."
fi

# 3. Download the files from the router (executes only if the router file is newer)
echo "sshing key..."
$SSH_CMD ${ROUTER_USER}@${ROUTER_IP} "cat ${CERT_PATH_ON_ROUTER}" > /ssl/cert.pem
echo "sshing cert..."
$SSH_CMD ${ROUTER_USER}@${ROUTER_IP} "cat ${KEY_PATH_ON_ROUTER}" > /ssl/privkey.pem

bashio::log.info "=== SUCCESS: New files have been saved to /ssl ==="

# 4. Dynamic status helper update section (executes only if statusHelper is configured)
if [ -n "$STATUS_HELPER" ]; then
    NEW_DATE=$(date "+%Y-%m-%d %H:%M:%S")
    bashio::log.info "Updating dynamic status helper [${STATUS_HELPER}] in Home Assistant..."
    
    curl -sS -X POST \
      -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{\"state\": \"Updated: ${NEW_DATE}\"}" \
      http://supervisor/core/api/states/${STATUS_HELPER}
      
    bashio::log.info "Status helper updated successfully!"
else
    bashio::log.info "The statusHelper field is empty. Skipping Home Assistant state update."
fi

bashio::log.info "Done. Exiting..."

# Official container shutdown command for s6-overlay v3
exec /run/s6/basedir/bin/halt

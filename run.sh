#!/usr/bin/with-contenv bashio
set -e

SSH_DIR=~/.ssh

ROUTER_USER="$(bashio::config 'sslFromAsusRouter.routerUser')"
ROUTER_IP="$(bashio::config 'sslFromAsusRouter.routerIp')"
ROUTER_PORT="$(bashio::config 'sslFromAsusRouter.routerSshPort')"
RSA_PRIVATE_KEY_PATH="$(bashio::config 'sslFromAsusRouter.rsaPrivateKeyPath')"
KEY_PATH_ON_ROUTER="$(bashio::config 'sslFromAsusRouter.keyFilePathOnRouter')"
CERT_PATH_ON_ROUTER="$(bashio::config 'sslFromAsusRouter.certFilePathOnRouter')"

echo "Getting Router Public RSA Key...."
ROUTER_RSA_KEY=$(ssh-keyscan -p ${ROUTER_PORT} -t rsa ${ROUTER_IP})

echo "Creating ${SSH_DIR}"
mkdir -p ${SSH_DIR}

echo "Setting id_rsa file..."
cp /config/"${RSA_PRIVATE_KEY_PATH}" ${SSH_DIR}/id_rsa
chmod 600 ${SSH_DIR}/id_rsa

echo "Touching ${SSH_DIR}/known_hosts..."
touch ${SSH_DIR}/known_hosts

echo "Setting ${SSH_DIR}/known_hosts Permission..."
ls -lrt ${SSH_DIR}

echo "Saving know hosts..."
if grep -q "${ROUTER_RSA_KEY}" ${SSH_DIR}/known_hosts; then
	echo "Already known host..."
else
	echo "Not known Host, adding..."
	chmod 777 ${SSH_DIR}/known_hosts
	echo "$ROUTER_RSA_KEY" >> ${SSH_DIR}/known_hosts
fi

chmod 644 ${SSH_DIR}/known_hosts;
cat ${SSH_DIR}/known_hosts

LOCAL_CERT="/ssl/cert.pem"

bashio::log.info "=== START AUTOMATYZACJI MÓJ FORK ==="

# Skrócona konfiguracja SSH dla czytelności kodu
SSH_CMD="ssh -v -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p ${ROUTER_PORT} -i /config/${RSA_PRIVATE_KEY_PATH}"

# 1. Sprawdzenie czy lokalny plik w ogóle istnieje
if [ -f "$LOCAL_CERT" ]; then
    bashio::log.info "Znaleziono lokalny certyfikat. Sprawdzam wersję na routerze..."
    
    # Pobieramy datę modyfikacji pliku lokalnego (w sekundach Unix)
    LOCAL_TIME=$(stat -c %Y "$LOCAL_CERT")
    bashio::log.info "$LOCAL_TIME"
    
    # Pobieramy datę modyfikacji pliku na routerze przez SSH
    REMOTE_TIME=$($SSH_CMD ${ROUTER_USER}@${ROUTER_IP} "date -r ${CERT_PATH_ON_ROUTER} +%s")
    bashio::log.info "$REMOTE_TIME"
    
    # Awaryjna weryfikacja na wypadek gdyby router nie zwrócił daty (np. brak polecenia stat)
    if [ -z "$REMOTE_TIME" ] || ! [ "$REMOTE_TIME" -eq "$REMOTE_TIME" ] 2>/dev/null; then
        bashio::log.warning "Nie udało się pobrać czasu z routera. Wymuszam pobieranie dla bezpieczeństwa."
        REMOTE_TIME=$((LOCAL_TIME + 1))
    fi

    # 2. Porównanie czasów
    if [ "$LOCAL_TIME" -ge "$REMOTE_TIME" ]; then
        bashio::log.info "Certyfikat w Home Assistant jest AKTUALNY (taki sam lub nowszy niż na routerze)."
        bashio::log.info "Kopiowanie pominięte."
        exit 0
		exec /run/s6/basedir/bin/halt
    else
        bashio::log.info "Wykryto nowszy certyfikat na routerze ASUS. Rozpoczynam pobieranie..."
    fi
else
    bashio::log.info "Brak lokalnego certyfikatu w /ssl. Pobieram po raz pierwszy..."
fi

bashio::log.info "=== SUKCES: Nowe pliki zostały zapisane w /ssl ==="
echo "sshing key..."
$SSH_CMD ${ROUTER_USER}@${ROUTER_IP} "cat ${CERT_PATH_ON_ROUTER}" > /ssl/cert.pem
echo "sshing cert..."
$SSH_CMD ${ROUTER_USER}@${ROUTER_IP} "cat ${KEY_PATH_ON_ROUTER}" > /ssl/privkey.pem

bashio::log.info "Done. Exiting..."

# Oficjalne polecenie zamknięcia kontenera dla s6-overlay v3
exec /run/s6/basedir/bin/halt

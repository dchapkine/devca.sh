#!/bin/bash
set -e

# Base directory for CA operations in ~/.devca
CA_DIR="$HOME/.devca"
CONFIG_FILE="$CA_DIR/openssl.cnf"

# Initialize CA directory structure and config if not present
init_ca() {
    mkdir -p "$CA_DIR"/{certs,crl,newcerts,private}
    chmod 700 "$CA_DIR/private"
    touch "$CA_DIR/index.txt"
    [ -f "$CA_DIR/serial" ] || echo '1000' > "$CA_DIR/serial"

    # Create a minimal OpenSSL configuration file if not exist
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" <<EOF
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = $CA_DIR
certs             = \$dir/certs
new_certs_dir     = \$dir/newcerts
database          = \$dir/index.txt
serial            = \$dir/serial
private_key       = \$dir/ca.key
certificate       = \$dir/ca.crt
default_days      = 365
default_md        = sha256
policy            = policy_any
x509_extensions   = usr_cert
copy_extensions   = copy

[ policy_any ]
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ req ]
default_bits        = 2048
default_keyfile     = privkey.pem
distinguished_name  = req_distinguished_name
string_mask         = utf8only

[ req_distinguished_name ]
countryName                     = Country Name (2 letter code)
stateOrProvinceName             = State or Province Name
localityName                    = Locality Name
0.organizationName              = Organization Name
organizationalUnitName          = Organizational Unit Name
commonName                      = Common Name (e.g. server FQDN or YOUR name)
emailAddress                    = Email Address

[ usr_cert ]
basicConstraints=CA:FALSE
nsCertType                      = client, email
nsComment                       = "OpenSSL Generated Client Certificate"
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EOF
    fi
}

# Initialize CA if not yet set up
init_ca

# Create CA key and certificate if they don't exist
if [ ! -f "$CA_DIR/ca.key" ] || [ ! -f "$CA_DIR/ca.crt" ]; then
    echo "Generating CA key and self-signed certificate..."
    openssl genrsa -out "$CA_DIR/ca.key" 4096
    openssl req -x509 -new -nodes -key "$CA_DIR/ca.key" -days 3650 \
        -out "$CA_DIR/ca.crt" -subj "/CN=LocalRootCA"
fi

# Usage message
usage() {
    echo "Usage:"
    echo "  $0 newcert <domain>"
    echo "  $0 newjks <alias> <keystore_path> <storepass> [SAN1 SAN2 ...]"
    echo "  $0 newtls <domain>"
    echo "  $0 install-ca"
    exit 1
}

# Function to detect OS
detect_os() {
    if [ "$(uname)" == "Darwin" ]; then
        echo "macos"
    elif [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

# Function to install CA globally
install_ca() {
    OS=$(detect_os)
    echo "Detected Operating System: $OS"

    CA_CERT="$CA_DIR/ca.crt"

    if [ ! -f "$CA_CERT" ]; then
        echo "CA certificate not found at $CA_CERT. Please generate it first."
        exit 1
    fi

    case "$OS" in
        ubuntu|debian)
            echo "Installing CA certificate on Debian/Ubuntu..."
            sudo cp "$CA_CERT" /usr/local/share/ca-certificates/devrootca.crt
            sudo update-ca-certificates
            ;;
        centos|rhel|fedora)
            echo "Installing CA certificate on RedHat/CentOS/Fedora..."
            sudo cp "$CA_CERT" /etc/pki/ca-trust/source/anchors/devrootca.crt
            sudo update-ca-trust extract
            ;;
        arch)
            echo "Installing CA certificate on Arch Linux..."
            sudo cp "$CA_CERT" /usr/share/pki/ca-trust-source/anchors/devrootca.crt
            sudo trust extract-compat
            ;;
        macos)
            echo "Installing CA certificate on macOS..."
            sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$CA_CERT"
            ;;
        *)
            echo "Unsupported Operating System: $OS"
            echo "Please install the CA certificate manually."
            exit 1
            ;;
    esac

    echo "CA certificate installed globally."
    import_chromium
}

# Function to import CA into Chromium
import_chromium() {
    echo "Importing CA certificate into Chromium..."

    OS=$(detect_os)
    case "$OS" in
        ubuntu|debian|centos|rhel|fedora|arch)
            echo "Chromium on Linux uses the system's trust store. Ensure the CA is installed globally."
            ;;
        macos)
            echo "Chromium on macOS uses the system's trust store. Ensure the CA is installed globally."
            ;;
        *)
            echo "Unsupported Operating System for Chromium CA import: $OS"
            echo "Please import the CA certificate into Chromium manually."
            ;;
    esac
    echo "CA certificate imported into Chromium (if necessary)."
}

# Command handling
COMMAND=$1

case "$COMMAND" in
    newcert)
        DOMAIN=$2
        [ -z "$DOMAIN" ] && usage

        DOMAIN_KEY="$CA_DIR/private/$DOMAIN.key"
        DOMAIN_CSR="$CA_DIR/$DOMAIN.csr"
        DOMAIN_CERT="$CA_DIR/certs/$DOMAIN.crt"

        echo "Generating private key for $DOMAIN..."
        openssl genrsa -out "$DOMAIN_KEY" 2048

        echo "Creating CSR for $DOMAIN..."
        openssl req -new -key "$DOMAIN_KEY" -out "$DOMAIN_CSR" -subj "/CN=$DOMAIN"

        # Create temporary extension file for SAN
        EXTFILE=$(mktemp)
        echo "subjectAltName = DNS:$DOMAIN" > "$EXTFILE"

        echo "Signing certificate for $DOMAIN using local CA..."
        openssl x509 -req -in "$DOMAIN_CSR" -CA "$CA_DIR/ca.crt" -CAkey "$CA_DIR/ca.key" \
            -CAcreateserial -out "$DOMAIN_CERT" -days 825 -sha256 \
            -extfile "$EXTFILE"

        rm "$EXTFILE"

        echo "Certificate signed:"
        echo "  Private Key: $DOMAIN_KEY"
        echo "  Certificate: $DOMAIN_CERT"
        ;;

    newjks)
        ALIAS=$2
        KEYSTORE=$3
        STOREPASS=$4
        shift 4
        SAN_ENTRIES=("$@")

        if [ ${#SAN_ENTRIES[@]} -gt 0 ]; then
            SAN_CONFIG=$(mktemp)
            cat > "$SAN_CONFIG" <<EOF
[ req ]
distinguished_name = req_distinguished_name
req_extensions = req_ext
prompt = no

[ req_distinguished_name ]
CN = localhost

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
EOF
            i=1
            for san in "${SAN_ENTRIES[@]}"; do
                echo "DNS.$i = $san" >> "$SAN_CONFIG"
                i=$((i+1))
            done

            echo "Generating private key and CSR for alias $ALIAS with SAN..."
            openssl req -new -nodes -newkey rsa:2048 \
              -keyout "$CA_DIR/$ALIAS-key.pem" -out "$CA_DIR/$ALIAS.csr" \
              -config "$SAN_CONFIG"

            echo "Signing certificate for alias $ALIAS using local CA with SAN..."
            openssl x509 -req -in "$CA_DIR/$ALIAS.csr" \
              -CA "$CA_DIR/ca.crt" -CAkey "$CA_DIR/ca.key" \
              -CAcreateserial -out "$CA_DIR/$ALIAS.crt" -days 825 -sha256 \
              -extfile "$SAN_CONFIG" -extensions req_ext

            echo "Creating PKCS#12 keystore..."
            openssl pkcs12 -export -in "$CA_DIR/$ALIAS.crt" \
              -inkey "$CA_DIR/$ALIAS-key.pem" \
              -chain -CAfile "$CA_DIR/ca.crt" -name "$ALIAS" \
              -out "$CA_DIR/$ALIAS-keystore.p12" -passout pass:"$STOREPASS"

            echo "Importing certificate chain into keystore..."
            keytool -importkeystore -deststorepass "$STOREPASS" -destkeypass "$STOREPASS" \
              -destkeystore "$KEYSTORE" -srckeystore "$CA_DIR/$ALIAS-keystore.p12" \
              -srcstoretype PKCS12 -srcstorepass "$STOREPASS" -alias "$ALIAS"

            rm -f "$SAN_CONFIG"
            echo "Keystore $KEYSTORE has been updated with a certificate signed by the local CA, including SANs."
        else
            echo "No SAN entries provided. Proceeding without SAN."
            # Fallback to original behavior without SAN
            ALIAS=$2
            KEYSTORE=$3
            STOREPASS=$4

            echo "Generating new keystore and key pair for alias $ALIAS..."
            keytool -genkeypair -alias "$ALIAS" -keyalg RSA -keysize 2048 \
              -keystore "$KEYSTORE" -storepass "$STOREPASS" -dname "CN=$ALIAS"

            echo "Generating CSR for alias $ALIAS..."
            keytool -certreq -alias "$ALIAS" -keystore "$KEYSTORE" -storepass "$STOREPASS" \
              -file "$CA_DIR/$ALIAS.csr"

            echo "Signing certificate for alias $ALIAS using local CA..."
            openssl x509 -req -in "$CA_DIR/$ALIAS.csr" \
              -CA "$CA_DIR/ca.crt" -CAkey "$CA_DIR/ca.key" \
              -CAcreateserial -out "$CA_DIR/$ALIAS.crt" -days 825 -sha256

            cat "$CA_DIR/$ALIAS.crt" "$CA_DIR/ca.crt" > "$CA_DIR/$ALIAS-chain.pem"

            echo "Importing certificate chain into keystore..."
            keytool -importcert -alias "$ALIAS" -file "$CA_DIR/$ALIAS-chain.pem" \
              -keystore "$KEYSTORE" -storepass "$STOREPASS" -noprompt

            echo "Keystore $KEYSTORE has been updated with a certificate signed by the local CA."
        fi
        ;;

    newtls)
        DOMAIN=$2
        [ -z "$DOMAIN" ] && usage

        TLS_KEY="$CA_DIR/private/$DOMAIN.key"
        TLS_CERT="$CA_DIR/certs/$DOMAIN.crt"
        TLS_CSR="$CA_DIR/$DOMAIN.csr"

        echo "Generating private key for $DOMAIN..."
        openssl genrsa -out "$TLS_KEY" 2048

        echo "Creating CSR for $DOMAIN..."
        openssl req -new -key "$TLS_KEY" -out "$TLS_CSR" -subj "/CN=$DOMAIN"

        # Create temporary extension file for SAN
        EXTFILE=$(mktemp)
        echo "subjectAltName = DNS:$DOMAIN" > "$EXTFILE"

        echo "Signing certificate for $DOMAIN with local CA..."
        openssl x509 -req -in "$TLS_CSR" -CA "$CA_DIR/ca.crt" -CAkey "$CA_DIR/ca.key" \
            -CAcreateserial -out "$TLS_CERT" -days 825 -sha256 \
            -extfile "$EXTFILE"

        rm "$EXTFILE"

        echo "PEM certificate and key generated:"
        echo "  Private Key: $TLS_KEY"
        echo "  Certificate: $TLS_CERT"
        ;;

    install-ca)
        install_ca
        ;;

    *)
        usage
        ;;
esac

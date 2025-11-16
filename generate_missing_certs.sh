#!/bin/bash

# Generate missing test certificates and keys
# This script creates all missing certificate files needed for test suite

set -e

PKI_DIR="PKI"
TEMP_DIR=$(mktemp -d)

trap "rm -rf $TEMP_DIR" EXIT

echo "=== Generating Missing Test Certificates ==="
echo "PKI Directory: $PKI_DIR"

# Create required directories
mkdir -p "$PKI_DIR/id_check"
mkdir -p "$PKI_DIR/revoked"
mkdir -p "$PKI_DIR/no-ocsp-uri"
mkdir -p "$PKI_DIR/unknown_certs"
mkdir -p "$PKI_DIR/ECC/door_certs"
mkdir -p "$PKI_DIR/ECC/door_req"

# ===== 1. Certificate with SAN extensions (has_san.pem) =====
echo "Generating has_san certificate with SAN extensions..."
openssl genrsa -out "$TEMP_DIR/has_san.key" 2048 2>/dev/null
cat > "$TEMP_DIR/has_san.conf" << 'EOF'
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = JP
ST = Tokyo
L = Tokyo
O = pivGateway
OU = test
CN = same.pivgateway.jp

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = same.pivgateway.jp
URI.1 = uuid:12345678-1234-5678-1234-567812345678
RFC822.1 = alt_email@pivgateway.jp
otherName.1 = 1.3.6.1.4.1.0.0:UTF8String:alt_upn@pivgateway.jp
EOF

openssl req -new -key "$TEMP_DIR/has_san.key" -config "$TEMP_DIR/has_san.conf" -out "$TEMP_DIR/has_san.csr" 2>/dev/null
openssl x509 -req -in "$TEMP_DIR/has_san.csr" \
  -signkey "$TEMP_DIR/has_san.key" \
  -out "$PKI_DIR/id_check/has_san.pem" \
  -days 3650 \
  -extensions v3_req \
  -extfile "$TEMP_DIR/has_san.conf" 2>/dev/null
cp "$TEMP_DIR/has_san.key" "$PKI_DIR/id_check/has_san.key"
echo "✓ Generated has_san.pem"

# ===== 2. Certificate without SAN extensions (no_san.pem) =====
echo "Generating no_san certificate without SAN extensions..."
openssl genrsa -out "$TEMP_DIR/no_san.key" 2048 2>/dev/null
cat > "$TEMP_DIR/no_san.conf" << 'EOF'
[req]
distinguished_name = req_distinguished_name
prompt = no

[req_distinguished_name]
C = JP
ST = Tokyo
L = Tokyo
O = pivGateway
OU = test
CN = same.pivgateway.jp
EOF

openssl req -new -key "$TEMP_DIR/no_san.key" -config "$TEMP_DIR/no_san.conf" -out "$TEMP_DIR/no_san.csr" 2>/dev/null
openssl x509 -req -in "$TEMP_DIR/no_san.csr" \
  -signkey "$TEMP_DIR/no_san.key" \
  -out "$PKI_DIR/id_check/no_san.pem" \
  -days 3650 2>/dev/null
cp "$TEMP_DIR/no_san.key" "$PKI_DIR/id_check/no_san.key"
echo "✓ Generated no_san.pem"

# ===== 3. Revoked user certificate (revoked-user3.pem) =====
echo "Generating revoked-user3 certificate..."
openssl genrsa -out "$TEMP_DIR/revoked-user3.key" 2048 2>/dev/null
cat > "$TEMP_DIR/revoked-user3.conf" << 'EOF'
[req]
distinguished_name = req_distinguished_name
prompt = no

[req_distinguished_name]
C = JP
ST = Tokyo
L = Tokyo
O = pivGateway
OU = reader
CN = revoked-user3
EOF

openssl req -new -key "$TEMP_DIR/revoked-user3.key" -config "$TEMP_DIR/revoked-user3.conf" -out "$TEMP_DIR/revoked-user3.csr" 2>/dev/null
openssl x509 -req -in "$TEMP_DIR/revoked-user3.csr" \
  -signkey "$TEMP_DIR/revoked-user3.key" \
  -out "$PKI_DIR/revoked/revoked-user3.pem" \
  -days 3650 \
  -set_serial 0x01 2>/dev/null
cp "$TEMP_DIR/revoked-user3.key" "$PKI_DIR/revoked/revoked-user3.key"
echo "✓ Generated revoked-user3.pem"

# ===== 4. Certificate without OCSP URI (no-ocsp-uri.pem) =====
echo "Generating no-ocsp-uri certificate..."
openssl genrsa -out "$TEMP_DIR/no-ocsp-uri.key" 2048 2>/dev/null
cat > "$TEMP_DIR/no-ocsp-uri.conf" << 'EOF'
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = JP
ST = Tokyo
L = Tokyo
O = pivGateway
OU = test
CN = no-ocsp-uri.pivgateway.jp

[v3_req]
subjectAltName = DNS:no-ocsp-uri.pivgateway.jp
EOF

openssl req -new -key "$TEMP_DIR/no-ocsp-uri.key" -config "$TEMP_DIR/no-ocsp-uri.conf" -out "$TEMP_DIR/no-ocsp-uri.csr" 2>/dev/null
openssl x509 -req -in "$TEMP_DIR/no-ocsp-uri.csr" \
  -signkey "$TEMP_DIR/no-ocsp-uri.key" \
  -out "$PKI_DIR/no-ocsp-uri/no-ocsp-uri.pem" \
  -days 3650 \
  -extensions v3_req \
  -extfile "$TEMP_DIR/no-ocsp-uri.conf" 2>/dev/null
cp "$TEMP_DIR/no-ocsp-uri.key" "$PKI_DIR/no-ocsp-uri/no-ocsp-uri.key"
echo "✓ Generated no-ocsp-uri.pem"

# ===== 5. Unknown CA signed certificate (unknown_certs/cmssigner.pem) =====
echo "Generating unknown_certs (signed by unknown CA)..."
# Create an unknown CA
openssl genrsa -out "$TEMP_DIR/unknown_ca.key" 2048 2>/dev/null
openssl req -new -x509 -key "$TEMP_DIR/unknown_ca.key" -out "$TEMP_DIR/unknown_ca.crt" -days 3650 \
  -subj "/C=JP/ST=Tokyo/L=Tokyo/O=UnknownOrg/OU=test/CN=unknown.ca" 2>/dev/null

# Generate certificate signed by unknown CA
openssl genrsa -out "$TEMP_DIR/cmssigner.key" 2048 2>/dev/null
cat > "$TEMP_DIR/cmssigner.conf" << 'EOF'
[req]
distinguished_name = req_distinguished_name
prompt = no

[req_distinguished_name]
C = JP
ST = Tokyo
L = Tokyo
O = UnknownOrg
OU = test
CN = cmssigner
EOF

openssl req -new -key "$TEMP_DIR/cmssigner.key" -config "$TEMP_DIR/cmssigner.conf" -out "$TEMP_DIR/cmssigner.csr" 2>/dev/null
openssl x509 -req -in "$TEMP_DIR/cmssigner.csr" \
  -CA "$TEMP_DIR/unknown_ca.crt" -CAkey "$TEMP_DIR/unknown_ca.key" \
  -out "$PKI_DIR/unknown_certs/cmssigner.pem" \
  -days 3650 -CAcreateserial 2>/dev/null
cp "$TEMP_DIR/cmssigner.key" "$PKI_DIR/unknown_certs/cmssigner.key"
echo "✓ Generated unknown_certs/cmssigner.pem"

# ===== 6. ECC Certificate (ECC/door_certs/door1.pem) =====
echo "Generating ECC door1 certificate..."
openssl ecparam -name prime256v1 -genkey -noout -out "$TEMP_DIR/ecc_door1.key"
cat > "$TEMP_DIR/ecc_door1.conf" << 'EOF'
[req]
distinguished_name = req_distinguished_name
prompt = no

[req_distinguished_name]
C = JP
ST = Tokyo
L = Tokyo
O = pivGateway
OU = door
CN = door1.pivgateway.jp
EOF

openssl req -new -key "$TEMP_DIR/ecc_door1.key" -config "$TEMP_DIR/ecc_door1.conf" -out "$TEMP_DIR/ecc_door1.csr" 2>/dev/null
openssl x509 -req -in "$TEMP_DIR/ecc_door1.csr" \
  -signkey "$TEMP_DIR/ecc_door1.key" \
  -out "$PKI_DIR/ECC/door_certs/door1.pem" \
  -days 3650 2>/dev/null
cp "$TEMP_DIR/ecc_door1.key" "$PKI_DIR/ECC/door_req/door1.key"
echo "✓ Generated ECC/door_certs/door1.pem"

# ===== 7. LDAP TLS client key (server_req/access_server.key) =====
echo "Generating LDAP TLS client key..."
openssl genrsa -out "$PKI_DIR/server_req/access_server.key" 2048 2>/dev/null
echo "✓ Generated server_req/access_server.key"

echo ""
echo "=== Certificate Generation Complete ==="
echo "Generated files:"
ls -lh "$PKI_DIR/id_check/"
ls -lh "$PKI_DIR/revoked/"
ls -lh "$PKI_DIR/no-ocsp-uri/"
ls -lh "$PKI_DIR/unknown_certs/"
ls -lh "$PKI_DIR/ECC/door_certs/"
ls -lh "$PKI_DIR/ECC/door_req/"
ls -lh "$PKI_DIR/server_req/access_server.key"

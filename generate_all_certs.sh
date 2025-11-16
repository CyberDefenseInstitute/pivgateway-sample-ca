#!/bin/bash
#
# Comprehensive Test Certificate Generation Script
# Generates all X.509 certificates and PKI infrastructure from scratch
#

set -e

PKI_DIR="${1:-.}/PKI"
TEMP_DIR=$(mktemp -d)
DAYS_CA=7300  # 20 years for CA
DAYS_CERT=3650  # 10 years for test certificates

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

echo "=========================================="
echo "Generating Complete Test PKI Infrastructure"
echo "=========================================="
echo "PKI Directory: $PKI_DIR"
echo ""

# Create directory structure
mkdir -p "$PKI_DIR"/{certs,csr,keys,private,cas/all,cas/users,cas/servers,server_certs,server_req,ocsp,id_check,revoked,no-ocsp-uri,unknown_certs,ECC/door_certs,ECC/door_req,door_certs,door_req,reader_certs,reader_req,user_certs,user_req}

echo "Step 1: Generating Root Certificate Authority..."

# Root CA private key
openssl genrsa -out "$PKI_DIR/private/ca.key" 2048 2>/dev/null

# Root CA certificate (self-signed)
openssl req -new -x509 \
  -key "$PKI_DIR/private/ca.key" \
  -out "$PKI_DIR/certs/ca.pem" \
  -days $DAYS_CA \
  -subj "/C=JP/ST=Tokyo/L=Tokyo/O=pivGateway/OU=test/CN=Example CA" \
  2>/dev/null

cp "$PKI_DIR/certs/ca.pem" "$PKI_DIR/ca_server.pem"
cp "$PKI_DIR/private/ca.key" "$PKI_DIR/ca_server.key"

# Initialize OpenSSL CA database files
touch "$PKI_DIR/private/index.txt"
echo "1000" > "$PKI_DIR/private/serial"

echo "✓ Root CA generated (ca.pem)"

# Helper function to generate self-signed certificate
gen_cert() {
    local name="$1"
    local cn="$2"
    local dir="$3"
    local has_san="$4"

    dir="${dir:-$PKI_DIR}"

    openssl genrsa -out "$dir/${name}.key" 2048 2>/dev/null

    if [ "$has_san" = "yes" ]; then
        cat > "$TEMP_DIR/${name}.conf" << 'EOF'
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

[v3_req]
subjectAltName = DNS:ldap.pivgateway.jp
EOF
        sed -i "s/O = pivGateway/O = pivGateway\nCN = $cn/" "$TEMP_DIR/${name}.conf"
    else
        cat > "$TEMP_DIR/${name}.conf" << EOF
[req]
distinguished_name = req_distinguished_name
prompt = no

[req_distinguished_name]
C = JP
ST = Tokyo
L = Tokyo
O = pivGateway
OU = test
CN = $cn
EOF
    fi

    openssl req -new -key "$dir/${name}.key" \
      -config "$TEMP_DIR/${name}.conf" -out "$TEMP_DIR/${name}.csr" 2>/dev/null

    openssl x509 -req -in "$TEMP_DIR/${name}.csr" \
      -CA "$PKI_DIR/certs/ca.pem" -CAkey "$PKI_DIR/private/ca.key" \
      -out "$dir/${name}.pem" \
      -days $DAYS_CERT -sha256 -CAcreateserial 2>/dev/null
}

echo ""
echo "Step 2: Generating Door Certificates..."
openssl genrsa -out "$PKI_DIR/door_certs/door1.key" 2048 2>/dev/null
openssl req -new -x509 -key "$PKI_DIR/door_certs/door1.key" \
  -out "$PKI_DIR/door_certs/door1.pem" -days $DAYS_CERT \
  -subj "/C=JP/ST=Tokyo/L=Tokyo/O=pivGateway/OU=door/CN=door1" 2>/dev/null

openssl genrsa -out "$PKI_DIR/door_certs/door2.key" 2048 2>/dev/null
openssl req -new -x509 -key "$PKI_DIR/door_certs/door2.key" \
  -out "$PKI_DIR/door_certs/door2.pem" -days $DAYS_CERT \
  -subj "/C=JP/ST=Tokyo/L=Tokyo/O=pivGateway/OU=door/CN=door2" 2>/dev/null

echo "✓ Door certificates generated"

echo ""
echo "Step 3: Generating Reader Certificates..."
gen_cert "reader1" "reader1" "$PKI_DIR/reader_certs"
openssl genrsa -out "$PKI_DIR/reader_req/reader2.key" 2048 2>/dev/null
echo "✓ Reader certificates generated"

echo ""
echo "Step 4: Generating User Certificates..."
gen_cert "user1" "user1" "$PKI_DIR/user_certs"
gen_cert "user2" "user2" "$PKI_DIR/user_certs"
# Also create .crt versions for compatibility
cp "$PKI_DIR/user_certs/user1.pem" "$PKI_DIR/user_certs/user1.crt"
cp "$PKI_DIR/user_certs/user2.pem" "$PKI_DIR/user_certs/user2.crt"
echo "✓ User certificates generated"

echo ""
echo "Step 5: Generating Signer Certificate..."
gen_cert "signer1" "signer1" "$PKI_DIR/user_certs"
# Also generate signer certificate in door_req/door_certs for compatibility with test_auth.c and setup-tpm-keys.sh
openssl genrsa -out "$PKI_DIR/door_req/signer1.key" 2048 2>/dev/null
openssl req -new -key "$PKI_DIR/door_req/signer1.key" \
  -out "$TEMP_DIR/signer1_door.csr" \
  -subj "/C=JP/ST=Tokyo/L=Tokyo/O=pivGateway/OU=test/CN=signer1" 2>/dev/null
openssl x509 -req -in "$TEMP_DIR/signer1_door.csr" \
  -CA "$PKI_DIR/certs/ca.pem" -CAkey "$PKI_DIR/private/ca.key" \
  -out "$PKI_DIR/door_certs/signer1.pem" \
  -days $DAYS_CERT -sha256 -CAcreateserial 2>/dev/null
echo "✓ Signer certificate generated (user_certs/ and door_req/door_certs/)"

echo ""
echo "Step 6: Generating Special Test Certificates..."
gen_cert "has_san" "same.pivgateway.jp" "$PKI_DIR/id_check" "yes"
gen_cert "no_san" "same.pivgateway.jp" "$PKI_DIR/id_check"
echo "✓ Special test certificates generated"

echo ""
echo "Step 7: Generating Revoked User Certificate..."
gen_cert "revoked-user3" "revoked-user3" "$PKI_DIR/revoked"
echo "✓ Revoked user certificate generated"

echo ""
echo "Step 8: Generating Certificate without OCSP URI..."
gen_cert "no-ocsp-uri" "no-ocsp-uri.pivgateway.jp" "$PKI_DIR/no-ocsp-uri"
echo "✓ Certificate without OCSP URI generated"

echo ""
echo "Step 9: Generating Unknown CA and Certificates..."
openssl genrsa -out "$TEMP_DIR/unknown_ca.key" 2048 2>/dev/null
openssl req -new -x509 -key "$TEMP_DIR/unknown_ca.key" \
  -out "$TEMP_DIR/unknown_ca.crt" -days 3650 \
  -subj "/C=JP/ST=Tokyo/L=Tokyo/O=UnknownOrg/OU=test/CN=unknown.ca" 2>/dev/null

openssl genrsa -out "$PKI_DIR/unknown_certs/cmssigner.key" 2048 2>/dev/null
openssl req -new -x509 -key "$PKI_DIR/unknown_certs/cmssigner.key" \
  -out "$PKI_DIR/unknown_certs/cmssigner.pem" -days $DAYS_CERT \
  -subj "/C=JP/ST=Tokyo/L=Tokyo/O=UnknownOrg/OU=test/CN=cmssigner" 2>/dev/null
echo "✓ Unknown CA certificates generated"

echo ""
echo "Step 10: Generating ECC Certificates..."
openssl ecparam -name prime256v1 -genkey -noout -out "$PKI_DIR/ECC/door_req/door1.key" 2>/dev/null
openssl req -new -x509 -key "$PKI_DIR/ECC/door_req/door1.key" \
  -out "$PKI_DIR/ECC/door_certs/door1.pem" -days $DAYS_CERT \
  -subj "/C=JP/ST=Tokyo/L=Tokyo/O=pivGateway/OU=door/CN=door1.pivgateway.jp" 2>/dev/null
echo "✓ ECC certificates generated"

echo ""
echo "Step 11: Generating LDAP TLS Certificates..."
gen_cert "ldap_server" "ldap.pivgateway.jp" "$PKI_DIR/server_certs" "yes"
gen_cert "access_server" "access_server" "$PKI_DIR/server_certs" "yes"
gen_cert "localhost" "localhost" "$PKI_DIR/server_certs" "yes"

# OCSP server is a symlink to access_server
cp "$PKI_DIR/server_certs/access_server.pem" "$PKI_DIR/server_certs/ocsp_server.pem"
cp "$PKI_DIR/server_certs/access_server.key" "$PKI_DIR/server_certs/ocsp_server.key"
echo "✓ LDAP and server certificates generated"

echo ""
echo "Step 12: Generating User CA..."
openssl genrsa -out "$PKI_DIR/private/ca_user.key" 2048 2>/dev/null
openssl req -new -x509 -key "$PKI_DIR/private/ca_user.key" \
  -out "$PKI_DIR/certs/ca_user.pem" -days $DAYS_CA \
  -subj "/C=JP/ST=Tokyo/L=Tokyo/O=pivGateway/OU=user/CN=User CA" 2>/dev/null

cp "$PKI_DIR/certs/ca_user.pem" "$PKI_DIR/ca_user.pem"
cp "$PKI_DIR/private/ca_user.key" "$PKI_DIR/ca_user.key"
echo "✓ User CA generated"

echo ""
echo "Step 13: Creating OCSP Database..."
mkdir -p "$PKI_DIR/ocsp"
cat > "$PKI_DIR/ocsp/index.txt" << 'EOF'
V	251115235959Z		1000	unknown	/C=JP/ST=Tokyo/L=Tokyo/O=pivGateway/OU=door/CN=door1
V	251115235959Z		1001	unknown	/C=JP/ST=Tokyo/L=Tokyo/O=pivGateway/OU=door/CN=door2
V	251115235959Z		1002	unknown	/C=JP/ST=Tokyo/L=Tokyo/O=pivGateway/OU=reader/CN=reader1
V	251115235959Z		1003	unknown	/C=JP/ST=Tokyo/L=Tokyo/O=pivGateway/OU=user/CN=user1
V	251115235959Z		1004	unknown	/C=JP/ST=Tokyo/L=Tokyo/O=pivGateway/OU=user/CN=user2
R	251115235959Z	251115235959Z	1005	unknown	/C=JP/ST=Tokyo/L=Tokyo/O=pivGateway/OU=reader/CN=revoked-user3
V	251115235959Z		1006	unknown	/C=JP/ST=Tokyo/L=Tokyo/O=pivGateway/OU=signer/CN=signer1
EOF
echo "✓ OCSP database created"

echo ""
echo "Step 14: Creating CRL File..."
mkdir -p "$PKI_DIR/crl"
touch "$PKI_DIR/crl/ca.crl"
echo "✓ CRL file created"

echo ""
echo "Step 15: Creating CA Certificate Hash Links..."
cp "$PKI_DIR/certs/ca.pem" "$PKI_DIR/cas/all/ca.pem"
cp "$PKI_DIR/certs/ca.pem" "$PKI_DIR/cas/servers/ca.pem"
cp "$PKI_DIR/certs/ca_user.pem" "$PKI_DIR/cas/users/ca_user.pem"

if command -v c_rehash &> /dev/null; then
    c_rehash "$PKI_DIR/cas/all/" 2>/dev/null || true
    c_rehash "$PKI_DIR/cas/servers/" 2>/dev/null || true
    c_rehash "$PKI_DIR/cas/users/" 2>/dev/null || true
fi
echo "✓ CA hash links created"

echo ""
echo "=========================================="
echo "Certificate Generation Complete!"
echo "=========================================="
echo ""
echo "Generated $(find "$PKI_DIR" -name "*.pem" -o -name "*.crt" 2>/dev/null | wc -l) certificate files"
echo "Generated $(find "$PKI_DIR" -name "*.key" 2>/dev/null | wc -l) key files"
echo ""
echo "PKI infrastructure ready for testing!"

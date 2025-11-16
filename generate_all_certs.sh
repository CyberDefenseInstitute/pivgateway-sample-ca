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
mkdir -p "$PKI_DIR"/{certs,csr,keys,private,cas/all,cas/users,cas/servers,server_certs,server_req,ocsp,id_check,revoked,no-ocsp-uri,unknown_certs,ECC/door_certs,ECC/door_req,door_certs,door_req,reader_certs,reader_req,user_certs,user_req,localhost,crl}

echo "Step 1: Generating Root Certificate Authority..."

# Root CA private key
openssl genrsa -out "$PKI_DIR/private/ca.key" 2048 2>/dev/null

# Root CA certificate (self-signed) with v3 extensions
cat > "$TEMP_DIR/ca.conf" << 'EOF'
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca
prompt = no

[req_distinguished_name]
C = JP
ST = Tokyo
L = Tokyo
O = pivGateway
OU = test
CN = Example CA

[v3_ca]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
EOF

openssl req -new -x509 \
  -key "$PKI_DIR/private/ca.key" \
  -out "$PKI_DIR/certs/ca.pem" \
  -days $DAYS_CA \
  -config "$TEMP_DIR/ca.conf" \
  2>/dev/null

cp "$PKI_DIR/certs/ca.pem" "$PKI_DIR/ca_server.pem"
cp "$PKI_DIR/private/ca.key" "$PKI_DIR/ca_server.key"

# Initialize OpenSSL CA database files
touch "$PKI_DIR/private/index.txt"
echo "1000" > "$PKI_DIR/private/serial"

echo "✓ Root CA generated (ca.pem)"

# OCSP Responder URI for all certificates
OCSP_URI="http://ocsp.pivgateway.jp:8080/ejbca/publicweb/status/ocsp"

# Helper function to generate CA-signed certificate with OCSP support
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

[v3_cert]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = emailProtection, codeSigning
authorityInfoAccess = OCSP;URI:http://ocsp.pivgateway.jp:8080/ejbca/publicweb/status/ocsp
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

[v3_cert]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = emailProtection, codeSigning
authorityInfoAccess = OCSP;URI:http://ocsp.pivgateway.jp:8080/ejbca/publicweb/status/ocsp
EOF
    fi

    openssl req -new -key "$dir/${name}.key" \
      -config "$TEMP_DIR/${name}.conf" -out "$TEMP_DIR/${name}.csr" 2>/dev/null

    openssl x509 -req -in "$TEMP_DIR/${name}.csr" \
      -CA "$PKI_DIR/certs/ca.pem" -CAkey "$PKI_DIR/private/ca.key" \
      -out "$dir/${name}.pem" \
      -days $DAYS_CERT -sha256 -CAcreateserial \
      -extfile "$TEMP_DIR/${name}.conf" -extensions v3_cert 2>/dev/null
}

echo ""
echo "Step 2: Generating Door Certificates..."

# Door1 certificate with v3 extensions
openssl genrsa -out "$PKI_DIR/door_certs/door1.key" 2048 2>/dev/null
cat > "$TEMP_DIR/door1.conf" << 'EOF'
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_cert
prompt = no

[req_distinguished_name]
C = JP
ST = Tokyo
L = Tokyo
O = pivGateway
OU = door
CN = door1

[v3_cert]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
EOF

openssl req -new -x509 -key "$PKI_DIR/door_certs/door1.key" \
  -out "$PKI_DIR/door_certs/door1.pem" -days $DAYS_CERT \
  -config "$TEMP_DIR/door1.conf" 2>/dev/null

# Door2 certificate with v3 extensions
openssl genrsa -out "$PKI_DIR/door_certs/door2.key" 2048 2>/dev/null
cat > "$TEMP_DIR/door2.conf" << 'EOF'
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_cert
prompt = no

[req_distinguished_name]
C = JP
ST = Tokyo
L = Tokyo
O = pivGateway
OU = door
CN = door2

[v3_cert]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
EOF

openssl req -new -x509 -key "$PKI_DIR/door_certs/door2.key" \
  -out "$PKI_DIR/door_certs/door2.pem" -days $DAYS_CERT \
  -config "$TEMP_DIR/door2.conf" 2>/dev/null

# Copy door keys to door_req/ for test compatibility
cp "$PKI_DIR/door_certs/door1.key" "$PKI_DIR/door_req/door1.key"
cp "$PKI_DIR/door_certs/door2.key" "$PKI_DIR/door_req/door2.key"

echo "✓ Door certificates generated"

echo ""
echo "Step 3: Generating Reader Certificates..."
gen_cert "reader1" "reader1" "$PKI_DIR/reader_certs"
openssl genrsa -out "$PKI_DIR/reader_req/reader2.key" 2048 2>/dev/null

# Also copy reader1 to door_certs/ and door_req/ for test compatibility
cp "$PKI_DIR/reader_certs/reader1.pem" "$PKI_DIR/door_certs/reader1.pem"
cp "$PKI_DIR/reader_certs/reader1.key" "$PKI_DIR/door_req/reader1.key"

echo "✓ Reader certificates generated"

echo ""
echo "Step 4: Generating User Certificates..."
gen_cert "user1" "user1" "$PKI_DIR/user_certs"
gen_cert "user2" "user2" "$PKI_DIR/user_certs"
# Also create .crt versions for compatibility
cp "$PKI_DIR/user_certs/user1.pem" "$PKI_DIR/user_certs/user1.crt"
cp "$PKI_DIR/user_certs/user2.pem" "$PKI_DIR/user_certs/user2.crt"
# Copy user keys to user_req/ for test compatibility (test_auth.c references user_req/)
cp "$PKI_DIR/user_certs/user1.key" "$PKI_DIR/user_req/user1.key"
cp "$PKI_DIR/user_certs/user2.key" "$PKI_DIR/user_req/user2.key"
echo "✓ User certificates generated"

echo ""
echo "Step 5: Generating Signer Certificate..."
gen_cert "signer1" "signer1" "$PKI_DIR/user_certs"
# Also generate signer certificate in door_req/door_certs for compatibility with test_auth.c and setup-tpm-keys.sh
openssl genrsa -out "$PKI_DIR/door_req/signer1.key" 2048 2>/dev/null

# Create OpenSSL config for signer1 door certificate with X.509v3 extensions
cat > "$TEMP_DIR/signer1_door.conf" << 'EOF'
[req]
distinguished_name = req_distinguished_name
prompt = no

[req_distinguished_name]
C = JP
ST = Tokyo
L = Tokyo
O = pivGateway
OU = test
CN = signer1

[v3_cert]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = emailProtection, codeSigning
EOF

openssl req -new -key "$PKI_DIR/door_req/signer1.key" \
  -config "$TEMP_DIR/signer1_door.conf" \
  -out "$TEMP_DIR/signer1_door.csr" 2>/dev/null
openssl x509 -req -in "$TEMP_DIR/signer1_door.csr" \
  -CA "$PKI_DIR/certs/ca.pem" -CAkey "$PKI_DIR/private/ca.key" \
  -out "$PKI_DIR/door_certs/signer1.pem" \
  -days $DAYS_CERT -sha256 -CAcreateserial \
  -extfile "$TEMP_DIR/signer1_door.conf" -extensions v3_cert 2>/dev/null
echo "✓ Signer certificate generated (user_certs/ and door_req/door_certs/)"

echo ""
echo "Step 6: Generating Special Test Certificates..."

# Certificate WITH SAN extensions (has_san.pem)
openssl genrsa -out "$PKI_DIR/id_check/has_san.key" 2048 2>/dev/null
cat > "$TEMP_DIR/has_san.conf" << 'EOF'
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = AU
ST = Some-State
O = Internet Widgits Pty Ltd
CN = same.pivgateway.jp
emailAddress = same@pivgateway.jp

[v3_req]
subjectAltName = @alt_names

[v3_cert]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = emailProtection, codeSigning
subjectAltName = @alt_names
authorityInfoAccess = OCSP;URI:http://ocsp.pivgateway.jp:8080/ejbca/publicweb/status/ocsp

[alt_names]
DNS.1 = same.pivgateway.jp
email.1 = alt_email@pivgateway.jp
otherName.1 = 1.3.6.1.4.1.311.20.2.3;UTF8:alt_upn@pivgateway.jp
URI.1 = uuid:XXXX-XXXXX-XXXXXX
EOF

openssl req -new -key "$PKI_DIR/id_check/has_san.key" \
  -config "$TEMP_DIR/has_san.conf" -out "$TEMP_DIR/has_san.csr" 2>/dev/null

openssl x509 -req -in "$TEMP_DIR/has_san.csr" \
  -CA "$PKI_DIR/certs/ca.pem" -CAkey "$PKI_DIR/private/ca.key" \
  -out "$PKI_DIR/id_check/has_san.pem" \
  -days $DAYS_CERT -sha256 -CAcreateserial \
  -extfile "$TEMP_DIR/has_san.conf" -extensions v3_cert 2>/dev/null

# Certificate WITHOUT SAN extensions (no_san.pem)
openssl genrsa -out "$PKI_DIR/id_check/no_san.key" 2048 2>/dev/null
cat > "$TEMP_DIR/no_san.conf" << 'EOF'
[req]
distinguished_name = req_distinguished_name
prompt = no

[req_distinguished_name]
C = AU
ST = Some-State
O = Internet Widgits Pty Ltd
CN = same.pivgateway.jp
emailAddress = same@pivgateway.jp

[v3_cert]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = emailProtection, codeSigning
authorityInfoAccess = OCSP;URI:http://ocsp.pivgateway.jp:8080/ejbca/publicweb/status/ocsp
EOF

openssl req -new -key "$PKI_DIR/id_check/no_san.key" \
  -config "$TEMP_DIR/no_san.conf" -out "$TEMP_DIR/no_san.csr" 2>/dev/null

openssl x509 -req -in "$TEMP_DIR/no_san.csr" \
  -CA "$PKI_DIR/certs/ca.pem" -CAkey "$PKI_DIR/private/ca.key" \
  -out "$PKI_DIR/id_check/no_san.pem" \
  -days $DAYS_CERT -sha256 -CAcreateserial \
  -extfile "$TEMP_DIR/no_san.conf" -extensions v3_cert 2>/dev/null

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

# Unknown CA with v3 extensions
openssl genrsa -out "$TEMP_DIR/unknown_ca.key" 2048 2>/dev/null
cat > "$TEMP_DIR/unknown_ca.conf" << 'EOF'
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca
prompt = no

[req_distinguished_name]
C = JP
ST = Tokyo
L = Tokyo
O = UnknownOrg
OU = test
CN = unknown.ca

[v3_ca]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
EOF

openssl req -new -x509 -key "$TEMP_DIR/unknown_ca.key" \
  -out "$TEMP_DIR/unknown_ca.crt" -days 3650 \
  -config "$TEMP_DIR/unknown_ca.conf" 2>/dev/null

# CMS Signer certificate with v3 extensions
openssl genrsa -out "$PKI_DIR/unknown_certs/cmssigner.key" 2048 2>/dev/null
cat > "$TEMP_DIR/cmssigner.conf" << 'EOF'
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_cert
prompt = no

[req_distinguished_name]
C = JP
ST = Tokyo
L = Tokyo
O = UnknownOrg
OU = test
CN = cmssigner

[v3_cert]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = emailProtection, codeSigning
EOF

openssl req -new -x509 -key "$PKI_DIR/unknown_certs/cmssigner.key" \
  -out "$PKI_DIR/unknown_certs/cmssigner.pem" -days $DAYS_CERT \
  -config "$TEMP_DIR/cmssigner.conf" 2>/dev/null
echo "✓ Unknown CA certificates generated"

echo ""
echo "Step 10: Generating ECC Certificates..."

# ECC certificate with v3 extensions
openssl ecparam -name prime256v1 -genkey -noout -out "$PKI_DIR/ECC/door_req/door1.key" 2>/dev/null
cat > "$TEMP_DIR/ecc_door1.conf" << 'EOF'
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_cert
prompt = no

[req_distinguished_name]
C = JP
ST = Tokyo
L = Tokyo
O = pivGateway
OU = door
CN = door1.pivgateway.jp

[v3_cert]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyAgreement
extendedKeyUsage = serverAuth, clientAuth
EOF

openssl req -new -x509 -key "$PKI_DIR/ECC/door_req/door1.key" \
  -out "$PKI_DIR/ECC/door_certs/door1.pem" -days $DAYS_CERT \
  -config "$TEMP_DIR/ecc_door1.conf" 2>/dev/null
echo "✓ ECC certificates generated"

echo ""
echo "Step 11: Generating LDAP TLS Certificates..."
gen_cert "ldap_server" "ldap.pivgateway.jp" "$PKI_DIR/server_certs" "yes"
gen_cert "access_server" "access_server" "$PKI_DIR/server_certs" "yes"
echo "✓ LDAP and server certificates generated"

echo ""
echo "Step 11a: Generating OCSP Responder Certificate..."

# OCSP Responder certificate with OCSPSigning extension
openssl genrsa -out "$PKI_DIR/server_certs/ocsp_server.key" 2048 2>/dev/null
cat > "$TEMP_DIR/ocsp_server.conf" << 'EOF'
[req]
distinguished_name = req_distinguished_name
prompt = no

[req_distinguished_name]
C = JP
ST = Tokyo
L = Tokyo
O = pivGateway
OU = OCSP
CN = OCSP Responder

[v3_ocsp]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, nonRepudiation
extendedKeyUsage = critical, OCSPSigning
EOF

openssl req -new -key "$PKI_DIR/server_certs/ocsp_server.key" \
  -config "$TEMP_DIR/ocsp_server.conf" -out "$TEMP_DIR/ocsp_server.csr" 2>/dev/null

openssl x509 -req -in "$TEMP_DIR/ocsp_server.csr" \
  -CA "$PKI_DIR/certs/ca.pem" -CAkey "$PKI_DIR/private/ca.key" \
  -out "$PKI_DIR/server_certs/ocsp_server.pem" \
  -days $DAYS_CERT -sha256 -CAcreateserial \
  -extfile "$TEMP_DIR/ocsp_server.conf" -extensions v3_ocsp 2>/dev/null

echo "✓ OCSP Responder certificate generated"

echo ""
echo "Step 11b: Generating localhost Certificates..."

# localhost certificate for WebSocket tests
gen_cert "localhost" "localhost" "$PKI_DIR/localhost"

# localhost gRPC client certificate
openssl genrsa -out "$PKI_DIR/localhost/localhost_grpc_client.key" 2048 2>/dev/null
cat > "$TEMP_DIR/localhost_grpc.conf" << 'EOF'
[req]
distinguished_name = req_distinguished_name
prompt = no

[req_distinguished_name]
C = JP
ST = Tokyo
L = Tokyo
O = pivGateway
OU = test
CN = localhost

[v3_cert]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
authorityInfoAccess = OCSP;URI:http://ocsp.pivgateway.jp:8080/ejbca/publicweb/status/ocsp
EOF

openssl req -new -key "$PKI_DIR/localhost/localhost_grpc_client.key" \
  -config "$TEMP_DIR/localhost_grpc.conf" -out "$TEMP_DIR/localhost_grpc.csr" 2>/dev/null

openssl x509 -req -in "$TEMP_DIR/localhost_grpc.csr" \
  -CA "$PKI_DIR/certs/ca.pem" -CAkey "$PKI_DIR/private/ca.key" \
  -out "$PKI_DIR/localhost/localhost_grpc_client.pem" \
  -days $DAYS_CERT -sha256 -CAcreateserial \
  -extfile "$TEMP_DIR/localhost_grpc.conf" -extensions v3_cert 2>/dev/null

echo "✓ localhost certificates generated"

echo ""
echo "Step 12: Generating User CA..."

# User CA with v3 extensions
openssl genrsa -out "$PKI_DIR/private/ca_user.key" 2048 2>/dev/null
cat > "$TEMP_DIR/ca_user.conf" << 'EOF'
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca
prompt = no

[req_distinguished_name]
C = JP
ST = Tokyo
L = Tokyo
O = pivGateway
OU = user
CN = User CA

[v3_ca]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
EOF

openssl req -new -x509 -key "$PKI_DIR/private/ca_user.key" \
  -out "$PKI_DIR/certs/ca_user.pem" -days $DAYS_CA \
  -config "$TEMP_DIR/ca_user.conf" 2>/dev/null

cp "$PKI_DIR/certs/ca_user.pem" "$PKI_DIR/ca_user.pem"
cp "$PKI_DIR/private/ca_user.key" "$PKI_DIR/ca_user.key"

# Also create .cer version for compatibility
cp "$PKI_DIR/certs/ca_user.pem" "$PKI_DIR/ca_user.cer"

echo "✓ User CA generated"

echo ""
echo "Step 12a: Generating CRL Files..."

# Initialize CRL number
echo "1000" > "$PKI_DIR/private/crlnumber"
echo "1000" > "$PKI_DIR/private/crlnumber_user"

# Generate CRL for Root CA
cat > "$TEMP_DIR/crl.conf" << EOF
[ca]
default_ca = CA_default

[CA_default]
database = $PKI_DIR/private/index.txt
crlnumber = $PKI_DIR/private/crlnumber
default_crl_days = 365
default_md = sha256
EOF

openssl ca -config "$TEMP_DIR/crl.conf" -gencrl \
  -keyfile "$PKI_DIR/private/ca.key" \
  -cert "$PKI_DIR/certs/ca.pem" \
  -out "$PKI_DIR/crl/ca.crl" 2>/dev/null || touch "$PKI_DIR/crl/ca.crl"

# Generate CRL for User CA
cat > "$TEMP_DIR/crl_user.conf" << EOF
[ca]
default_ca = CA_default

[CA_default]
database = $PKI_DIR/private/index.txt
crlnumber = $PKI_DIR/private/crlnumber_user
default_crl_days = 365
default_md = sha256
EOF

openssl ca -config "$TEMP_DIR/crl_user.conf" -gencrl \
  -keyfile "$PKI_DIR/private/ca_user.key" \
  -cert "$PKI_DIR/certs/ca_user.pem" \
  -out "$PKI_DIR/crl/ca_user.crl" 2>/dev/null || touch "$PKI_DIR/crl/ca_user.crl"

# Copy CRL to root for compatibility
cp "$PKI_DIR/crl/ca.crl" "$PKI_DIR/ca.crl" 2>/dev/null || touch "$PKI_DIR/ca.crl"
cp "$PKI_DIR/crl/ca_user.crl" "$PKI_DIR/ca_user.crl" 2>/dev/null || touch "$PKI_DIR/ca_user.crl"

echo "✓ CRL files generated"

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

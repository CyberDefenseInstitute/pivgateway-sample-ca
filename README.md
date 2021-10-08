# PIV Gateway Sample CA

本レポジトリに`検証目的`のための認証局及びサーバ、クライアントの電子証明書を保存しています。

注意: 商用利用ではお客様にて準備した認証局を準備し証明書を発行ください。

## 認証局

CN = Example CA

ca.crt が公開鍵証明書、ca.key が秘密鍵となります。

## サーバ証明書

### LDAP向けサーバ

CN = ldap.server.example.com
SAN = DNS:ldap.server.example.com
X509v3 Extended Key Usage: TLS Web Server Authentication

ldap.server.example.com.crt が公開鍵証明書、ldap.server.example.com.key が秘密鍵となります。


### PIV Gateway サーバ

CN = pivgateway.server.example.com
SAN = DNS:pivgateway.server.example.com
X509v3 Extended Key Usage: TLS Web Server Authentication, TLS Web Client Authentication

pivgateway.server.example.com.crt が公開鍵証明書、pivgateway.server.example.com.key が秘密鍵となります。

### ドア向けカードリーダ

CN = room1
SAN:email:room1@example.com
X509v3 Extended Key Usage: TLS Web Server Authentication, TLS Web Client Authentication, E-mail Protection

room1.crt が公開鍵証明書、room1.key が秘密鍵となります。

## クライアント証明書

CN = Robert Smith
emailAddress = rsmith@example.com
SAN: email:rsmith@example.com
X509v3 Extended Key Usage: TLS Web Client Authentication

Robert_Smith.pfx を[Yubikey Manager](https://www.yubico.com/support/download/yubikey-manager/)を利用してYubikey 5 NFCに証明書をインポートしてください。

手順は以下の通りとなります。

Yubikey Manager  ->  Applications  -> PIV  -> Certificates [Configure Certificates] -> Card Authentication -> Import  ->  Robert_Smith.pfx をインポート(パスワードは設定されていません)



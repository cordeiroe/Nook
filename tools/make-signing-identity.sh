#!/bin/bash
# Cria um certificado de assinatura de codigo autoassinado e estavel.
#
# Por que: o macOS identifica um app pelo "requisito designado" da assinatura.
# Com assinatura ad-hoc esse requisito e o hash do binario, que muda a cada
# build, entao cada build vira um app novo e o sistema repete todo pedido de
# permissao: Keychain, EventKit, Automacao, pastas protegidas.
#
# Assinando com um certificado fixo o requisito vira:
#   identifier "<seu.bundle.id>" and certificate leaf = H"<hash>"
# que nao depende do binario. As autorizacoes sobrevivem a rebuilds.
#
# O certificado e local e autoassinado. Nao precisa ser confiado pelo sistema
# nem de sudo: o codesign so precisa da chave privada no chaveiro. Isso NAO
# substitui uma conta Apple Developer, necessaria apenas para distribuir a
# terceiros com notarizacao.
#
# ATENCAO: recriar o certificado gera um hash novo e zera as permissoes ja
# concedidas. Rode isto uma vez so.
set -euo pipefail

NAME="${1:-TokenDeck Dev}"

if security find-identity | grep -q "\"$NAME\""; then
    echo "identidade \"$NAME\" já existe"
    security find-identity | grep "\"$NAME\""
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PW="import-$$"

cat > "$WORK/openssl.cnf" <<CNF
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no

[ dn ]
CN = $NAME

[ ext ]
basicConstraints     = critical,CA:false
keyUsage             = critical,digitalSignature
extendedKeyUsage     = critical,codeSigning
subjectKeyIdentifier = hash
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$WORK/openssl.cnf" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null

# -legacy e -macalg sha1: o `security import` do macOS nao le o PKCS12 que o
# OpenSSL 3 gera por padrao, e falha com "MAC verification failed".
openssl pkcs12 -export -legacy -macalg sha1 \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/identity.p12" -passout "pass:$PW" 2>/dev/null

# -T autoriza o codesign a usar a chave sem pedir senha a cada assinatura.
security import "$WORK/identity.p12" \
    -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "$PW" -T /usr/bin/codesign

echo "identidade \"$NAME\" criada"
security find-identity | grep "\"$NAME\""

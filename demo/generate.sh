#!/bin/bash

set -e

if [ -e pki ]; then
  echo 'pki/ already exists (rm -rf it if you will)' >&2
  exit 1
fi

docker run -v $(pwd):/workdir -w /workdir --rm -it \
  -e ROOT_CN=DEMO \
  shyiko/openvpn:2.4.0_easyrsa-3.0.3 \
  bash -c '
  export EASYRSA_PKI=$(pwd)/pki
  easyrsa init-pki
  printf "$ROOT_CN\n" | easyrsa build-ca nopass
  easyrsa gen-crl
  easyrsa build-server-full server nopass
  easyrsa gen-dh
  openvpn --genkey --secret ta.key
  '

docker run -v $(pwd):/workdir -w /workdir --rm -it \
  -e REMOTE_HOST=minikube \
  -e REMOTE_PORT=1194 \
  -e CLIENT_NAME=jean-luc.picard \
  shyiko/openvpn:2.4.0_easyrsa-3.0.3 \
  bash -c '
  export EASYRSA_PKI=$(pwd)/pki
  easyrsa build-client-full $CLIENT_NAME nopass
  printf "# $(date -u +%FT%TZ)
client
verb 3
remote $REMOTE_HOST $REMOTE_PORT
persist-key
persist-tun
proto udp
nobind
dev tun
cipher AES-128-GCM
<ca>\n$(cat pki/ca.crt)\n</ca>
<key>\n$(cat pki/private/$CLIENT_NAME.key)\n</key>
<cert>\n$(cat pki/issued/$CLIENT_NAME.crt)\n</cert>
<dh>\n$(cat pki/dh.pem)\n</dh>
remote-cert-tls server
<tls-auth>\n$(cat ta.key)\n</tls-auth>
key-direction 1
" > /workdir/$CLIENT_NAME.ovpn
  '

sudo chown -R $(whoami) .

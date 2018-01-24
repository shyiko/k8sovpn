#!/bin/bash

set -e

CLIENT_EXTRA_ARGS=
if [[ "$OSTYPE" =~ linux ]]; then
  CLIENT_EXTRA_ARGS="
    --setenv PATH '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
    --script-security 2
    --up /etc/openvpn/update-resolv-conf.sh
    --down /etc/openvpn/update-resolv-conf.sh
  "
fi

sudo openvpn \
  $CLIENT_EXTRA_ARGS \
  --remote $(minikube ip) $( \
      kubectl get svc k8sovpn -o=jsonpath='{.spec.ports[?(@.port==1194)].nodePort}' \
    ) \
  --config jean-luc.picard.ovpn

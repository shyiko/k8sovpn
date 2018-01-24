FROM buildpack-deps:stretch-curl

RUN apt-get update && \
    apt-get install -y openvpn iptables && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /opt/easyrsa && \
    curl -sSL https://github.com/OpenVPN/easy-rsa/releases/download/v3.0.3/EasyRSA-3.0.3.tgz | \
      tar -xz -C /opt/easyrsa --strip-components=1

ENV PATH /opt/easyrsa:$PATH

EXPOSE 1194/tcp
EXPOSE 1194/udp

CMD openvpn --config /etc/openvpn/openvpn.conf

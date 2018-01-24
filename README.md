# k8sovpn

[OpenVPN](https://openvpn.net/index.php/open-source/documentation/howto.html) for Kubernetes.  
The primary goal is "to see the world the way pods see it".  

In other words, once connected these should work:

```sh
ping -4 service-name.namespace
ping -4 service-name.namespace.svc
ping -4 service-name.namespace.svc.cluster.local
```

## Usage

> If you don't want to use [shyiko/openvpn](https://hub.docker.com/r/shyiko/openvpn/) image - build your own with `docker build -t image:tag .` ([Dockerfile](Dockerfile) is included in this repo).  
(NOTE: any image with openvpn 2+ and easyrsa 3 will do, e.g. [kylemanna/docker-openvpn](https://github.com/kylemanna/docker-openvpn))

Set up OpenVPN server:

```sh
# generate
# - CA certificate/private key;
# - server certificate/private key;
# - Diffie-Hellman parameters file;
# - tls-auth key.
# 
# output:  
# ./pki/ca.crt
# ./pki/crl.pem
# ./pki/dh.pem
# ./pki/issued/server.crt
# ./pki/private/ca.key
# ./pki/private/server.key
# ./ta.key
#
docker run -v $(pwd):/workdir -w /workdir --rm -it \
  -e ROOT_CN=<hostname-or-anything-else-to-identify-ca-cert> \
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

# create a secret containing everything but CA private key (keep it safe!)
kubectl create secret generic k8sovpn \
  --from-file=pki/ca.crt \
  --from-file=pki/crl.pem \
  --from-file=pki/dh.pem \
  --from-file=pki/issued/server.crt \
  --from-file=pki/private/server.key \
  --from-file=ta.key

# deploy OpenVPN server
kubectl apply -f k8sovpn.yml
kubectl expose -f k8sovpn.yml --port=1194
```

That's it.  
You now have OpenVPN server running inside Kubernetes cluster.  
To connect:

```sh
# generate client certificate/private key and then pack everything in .ovpn 
# (OpenVPN client configuration)
#
# output:  
# ./pki/issued/$CLIENT_NAME.crt
# ./pki/private/$CLIENT_NAME.key
# ./$CLIENT_NAME.ovpn
#
docker run -v $(pwd):/workdir -w /workdir --rm -it \
  -e REMOTE_HOST=<openvpn-server-hostname-or-ip-address> \
  -e REMOTE_PORT=<openvpn-server-port-1194-by-default> \
  -e CLIENT_NAME=<client_name> \
  shyiko/openvpn:2.4.0_easyrsa-3.0.3 \
  bash -c '
  export EASYRSA_PKI=$(pwd)/pki
  easyrsa build-client-full $CLIENT_NAME nopass
  printf "client
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

# connect
sudo openvpn <client_name>.ovpn
```

> NOTE: .ovpn generated above has certs, client/tls-auth keys and DH params embedded 
(which means only .ovpn file needs to be distributed to the client (no need for separate ca.crt, dh.pem or ta.key)).

To revoke client certificate (in case you ever need this):

```sh
docker run -v $(pwd):/workdir -w /workdir --rm -it \
  -e CLIENT_NAME=<client_name> \
  shyiko/openvpn:2.4.0_easyrsa-3.0.3 \
  bash -c '
  export EASYRSA_PKI=$(pwd)/pki
  printf "yes\n" | easyrsa revoke $CLIENT_NAME
  easyrsa gen-crl
  '

# propagate updated CRL to the OpenVPN server

kubectl create secret generic k8sovpn \
  --from-file=pki/ca.crt \
  --from-file=pki/crl.pem \
  --from-file=pki/dh.pem \
  --from-file=pki/issued/server.crt \
  --from-file=pki/private/server.key \
  --from-file=ta.key

kubectl replace --force -f k8sovpn.yml
```

## DEMO (aka Testing locally via Minikube)

```sh
git clone https://github.com/shyiko/k8sovpn
cd demo/

minikube start

kubectl run nginx --image=nginx
kubectl expose deployment nginx --port=80

# all the certs/keys included in demo/ are for demo purposes only
# see "Usage" on how to generate your own
kubectl create secret generic k8sovpn \
  --from-file=pki/ca.crt \
  --from-file=pki/crl.pem \
  --from-file=pki/dh.pem \
  --from-file=pki/issued/server.crt \
  --from-file=pki/private/server.key \
  --from-file=ta.key
kubectl apply -f ../k8sovpn.yml
kubectl expose -f ../k8sovpn.yml --port=1194 --type=NodePort

# connect * (see footnote)
sudo openvpn \
  --remote $(minikube ip) $( \
      kubectl get svc k8sovpn -o=jsonpath='{.spec.ports[?(@.port==1194)].nodePort}' \
    ) \
  --config jean-luc.picard.ovpn

# try reaching nginx
curl -v http://nginx.default/
```

> \* on Linux you may need [masterkorp/openvpn-update-resolv-conf](https://github.com/masterkorp/openvpn-update-resolv-conf)  
([prepend](demo/openvpn-connect.sh) `--setenv PATH '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' --script-security 2 --up /etc/openvpn/update-resolv-conf.sh --down /etc/openvpn/update-resolv-conf.sh` to the list of `openvpn` args).

## Alternatives

[sshuttle](http://sshuttle.readthedocs.io/en/stable/) - Transparent proxy server over SSH that supports DNS tunneling.  

## Legal

All code, unless specified otherwise, is licensed under the [MIT](https://opensource.org/licenses/MIT) license.  
Copyright (c) 2018 Stanley Shyiko.

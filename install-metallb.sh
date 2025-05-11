#!/bin/bash

echo -e "\n\n\n"
echo -e "${GREEN}Configuring kube-proxy...${NO_COLOR}"

# see what changes would be made, returns nonzero returncode if different
kubectl get configmap kube-proxy -n kube-system -o yaml | \
sed -e "s/strictARP: false/strictARP: true/" | \
kubectl diff -f - -n kube-system

# actually apply the changes, returns nonzero returncode on errors only
kubectl get configmap kube-proxy -n kube-system -o yaml | \
sed -e "s/strictARP: false/strictARP: true/" | \
kubectl apply -f - -n kube-system

echo -e "${GREEN}Configuring MetalLB...${NO_COLOR}"
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml

kubectl wait --for=condition=Ready -n metallb-system pod -l app=metallb  --timeout=180s
sleep 5
kubectl apply -f manifests/metallb/ip-pool.yaml

echo -e "${GREEN}MetalLB configured successfully!${NO_COLOR}"

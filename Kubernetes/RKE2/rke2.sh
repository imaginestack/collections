#!/bin/bash

set -e

#############################################
# YOU SHOULD ONLY NEED TO EDIT THIS SECTION #
#############################################

# Version of Kube-VIP to deploy
KVVERSION="v0.8.0"

# Set the IP addresses of the admin, masters, and workers nodes
master1=192.168.10.31
master2=192.168.10.32
master3=192.168.10.33

# User of remote machines
user=cto

# Interface used on remotes
interface=enp0s31f6

# Set the virtual IP address (VIP)
vip=192.168.10.77

# Array of all master nodes
allmasters=($master1 $master2 $master3)

# Array of master nodes
masters=($master2 $master3)

# Array of all
all=($master1 $master2 $master3)

# Array of all minus master1
allnomaster1=($master2 $master3 )

# Loadbalancer IP range
lbrange=192.168.10.60-192.168.10.70

# SSH certificate name variable
certName=id_ed25519.3

#############################################
#            DO NOT EDIT BELOW              #
#############################################

# Ensure NTP is set
sudo timedatectl set-ntp off
sudo timedatectl set-ntp on

# Ensure SSH certs are in place
chmod 600 /home/$user/.ssh/$certName 
chmod 644 /home/$user/.ssh/$certName.pub

# Install kubectl if not present
if ! command -v kubectl &> /dev/null
then
    echo -e " \033[31;5mKubectl not found, installing\033[0m"
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
else
    echo -e " \033[32;5mKubectl already installed\033[0m"
fi

# Create SSH config to ignore host key checking (not recommended for production)
if ! grep -Fxq "StrictHostKeyChecking no" ~/.ssh/config
then
    echo "StrictHostKeyChecking no" | sudo tee -a ~/.ssh/config
fi

# Add SSH keys for all nodes
for node in "${all[@]}"; do
  ssh-copy-id -i /home/$user/.ssh/$certName.pub $user@$node
done

# Create RKE2 manifest directory and Kube-VIP manifest
sudo mkdir -p /var/lib/rancher/rke2/server/manifests
curl -sO https://raw.githubusercontent.com/imaginestack/collections/main/Kubernetes/RKE2/kube-vip
sed 's/$interface/'$interface'/g; s/$vip/'$vip'/g' kube-vip > $HOME/kube-vip.yaml
sudo mv $HOME/kube-vip.yaml /var/lib/rancher/rke2/server/manifests/kube-vip.yaml

# Update Kube-VIP manifest for RKE2
sudo sed -i 's/k3s/rke2/g' /var/lib/rancher/rke2/server/manifests/kube-vip.yaml

# Create RKE2 config file
sudo mkdir -p /etc/rancher/rke2
cat <<EOF | sudo tee /etc/rancher/rke2/config.yaml
tls-san:
  - $vip
  - $master1
  - $master2
  - $master3
write-kubeconfig-mode: 0644
disable:
  - rke2-ingress-nginx
EOF

# Update bash profile for kubectl and RKE2
if ! grep -Fxq "export KUBECONFIG=/etc/rancher/rke2/rke2.yaml" ~/.bashrc
then
    echo 'export KUBECONFIG=/etc/rancher/rke2/rke2.yaml' >> ~/.bashrc
    echo 'export PATH=${PATH}:/var/lib/rancher/rke2/bin' >> ~/.bashrc
    echo 'alias k=kubectl' >> ~/.bashrc
    source ~/.bashrc
fi

# Copy kube-vip.yaml and SSH certs to all master nodes
for newnode in "${allmasters[@]}"; do
  scp -i ~/.ssh/$certName $HOME/kube-vip.yaml $user@$newnode:~/kube-vip.yaml
  scp -i ~/.ssh/$certName /etc/rancher/rke2/config.yaml $user@$newnode:~/config.yaml
  scp -i ~/.ssh/$certName ~/.ssh/{$certName,$certName.pub} $user@$newnode:~/.ssh
  echo -e " \033[32;5mCopied successfully to $newnode\033[0m"
done

# Connect to master1, install RKE2, and start the server
ssh -tt $user@$master1 -i ~/.ssh/$certName <<EOF
sudo mv ~/kube-vip.yaml /var/lib/rancher/rke2/server/manifests/kube-vip.yaml
sudo mv ~/config.yaml /etc/rancher/rke2/config.yaml
echo 'export KUBECONFIG=/etc/rancher/rke2/rke2.yaml' >> ~/.bashrc
echo 'export PATH=${PATH}:/var/lib/rancher/rke2/bin' >> ~/.bashrc
echo 'alias k=kubectl' >> ~/.bashrc
source ~/.bashrc
curl -sfL https://get.rke2.io | sudo sh -
sudo systemctl enable rke2-server.service
sudo systemctl start rke2-server.service
sleep 30
if sudo systemctl is-active --quiet rke2-server.service; then
    echo -e " \033[32;5mRKE2 server is running on $master1\033[0m"
else
    echo -e " \033[31;5mRKE2 server failed to start on $master1\033[0m"
    exit 1
fi
scp -i /home/$user/.ssh/$certName /var/lib/rancher/rke2/server/token $user@$master1:~/token
scp -i /home/$user/.ssh/$certName /etc/rancher/rke2/rke2.yaml $user@$master1:~/.kube/rke2.yaml
exit
EOF

# Export the token
token=$(ssh -i ~/.ssh/$certName $user@$master1 "cat ~/token")

# Join other master nodes to the cluster
for newnode in "${masters[@]}"; do
  ssh -tt $user@$newnode -i ~/.ssh/$certName <<EOF
  sudo mv ~/config.yaml /etc/rancher/rke2/config.yaml
  echo "token: $token" | sudo tee -a /etc/rancher/rke2/config.yaml
  echo "server: https://$vip:9345" | sudo tee -a /etc/rancher/rke2/config.yaml
  echo 'export KUBECONFIG=/etc/rancher/rke2/rke2.yaml' >> ~/.bashrc
  echo 'export PATH=${PATH}:/var/lib/rancher/rke2/bin' >> ~/.bashrc
  echo 'alias k=kubectl' >> ~/.bashrc
  source ~/.bashrc
  curl -sfL https://get.rke2.io | sudo sh -
  sudo systemctl enable rke2-server.service
  sudo systemctl start rke2-server.service
  sleep 30
  if sudo systemctl is-active --quiet rke2-server.service; then
      echo -e " \033[32;5mRKE2 server is running on $newnode\033[0m"
  else
      echo -e " \033[31;5mRKE2 server failed to start on $newnode\033[0m"
      exit 1
  fi
  exit
EOF
done

# Set correct permissions for the directory and files
sudo chown -R cto:cto /var/lib/rancher/rke2/server/tls/
sudo chmod -R 750 /var/lib/rancher/rke2/server/tls/

# Verify the nodes
kubectl get nodes

# Step 8: Install Metallb
echo -e " \033[32;5mDeploying Metallb\033[0m"
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml
# Download ipAddressPool and configure using lbrange above
curl -sO https://raw.githubusercontent.com/imaginestack/collections/main/Kubernetes/RKE2/ipAddressPool
cat ipAddressPool | sed 's/$lbrange/'$lbrange'/g' > $HOME/ipAddressPool.yaml

# Step 9: Deploy IP Pools and l2Advertisement
echo -e " \033[32;5mAdding IP Pools, waiting for Metallb to be available first. This can take a long time as we're likely being rate limited for container pulls...\033[0m"
kubectl wait --namespace metallb-system \
                --for=condition=ready pod \
                --selector=component=controller \
                --timeout=1800s
kubectl apply -f ipAddressPool.yaml
kubectl apply -f https://raw.githubusercontent.com/imaginestack/collections/main/Kubernetes/RKE2/l2Advertisement.yaml

# Step 10: Install Rancher (Optional - Delete if not required)
#Install Helm
echo -e " \033[32;5mInstalling Helm\033[0m"
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# Add Rancher Helm Repo & create namespace
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
kubectl create namespace cattle-system

# Install Cert-Manager
echo -e " \033[32;5mDeploying Cert-Manager\033[0m"
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.crds.yaml
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
--namespace cert-manager \
--create-namespace \
--version v1.13.2
kubectl get pods --namespace cert-manager

# Install Rancher
echo -e " \033[32;5mDeploying Rancher\033[0m"
helm install rancher rancher-latest/rancher \
 --namespace cattle-system \
 --set hostname=dash.imaginestack.net \
 --set bootstrapPassword=admin
kubectl -n cattle-system rollout status deploy/rancher
kubectl -n cattle-system get deploy rancher

# Add Rancher LoadBalancer
kubectl get svc -n cattle-system
kubectl expose deployment rancher --name=rancher-lb --port=443 --type=LoadBalancer -n cattle-system
while [[ $(kubectl get svc -n cattle-system 'jsonpath={..status.conditions[?(@.type=="Pending")].status}') = "True" ]]; do
   sleep 5
   echo -e " \033[32;5mWaiting for LoadBalancer to come online\033[0m" 
done
kubectl get svc -n cattle-system

echo -e " \033[32;5mAccess Rancher from the IP above - Password is admin!\033[0m"

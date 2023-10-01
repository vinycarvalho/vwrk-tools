#!/bin/bash

# Get options
while getopts "s:n:t:c:" arg; do
  case $arg in
    s)
      ip_arg=$OPTARG
      ;;
    s)
      net_arg=$OPTARG
      ;;
    t)
     token_arg=$OPTARG
      ;;
    c)
      ca_arg=$OPTARG
      ;;
  esac
done

[[ -z $net_arg ]] && pod_network="10.10.0.0/16" || pod_network=$net_arg

if [[ -z $net_arg ]]; then
	ip_apiserver=$(ip r g 8.8.8.8 | sed -rn 's/.* src ([0-9.]+) .*$/\1/p')
else
	ip_apiserver=$ip_arg
fi

[[ -z token_arg ]] && [[ -z $ca_arg ]] && is_worker=1

# Conferindo o user root
userName=$(whoami)

if [[ $userName != "root" ]]; then
	echo "Need run as root"
fi

# turn off swap 
swapoff -a

# turn on kernel modules
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Kernel confs
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system


# Install kubernetes
apt -y update 
apt -y install apt-transport-https curl

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -

echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" >> /etc/apt/sources.list.d/kubernetes.list

apt -y update
apt -y install kubelet kubeadm kubectl

apt-mark hold kubelet kubeadm kubectl

# Install containerd
apt -y update
apt -y install apt-transport-https ca-certificates curl gnupg lsb-release

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

apt -y update 
apt -y install containerd.io

# Config containerd
containerd config default > /etc/containerd/config.toml

sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# Config services
systemctl restart containerd
systemctl status containerd

systemctl enable --now kubelet

if [[ $is_worker ]]; then
	echo "Worker!"
else
	# Start control pane
	kubeadm init --pod-network-cidr=$pod_network --apiserver-advertise-address=$ip_apiserver
fi

# Config kubeadm
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config


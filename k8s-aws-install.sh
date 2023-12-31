#!/bin/bash

# Get options
while getopts "a:c:n:s:t:" arg; do
  case $arg in
    a)
      ip_control_arg=$OPTARG
      ;;
    c)
      ca_arg=$OPTARG
      ;;
    n)
      net_arg=$OPTARG
      ;;
    s)
      ip_arg=$OPTARG
      ;;
    t)
     token_arg=$OPTARG
      ;;
  esac
done

[[ -z $net_arg ]] && pod_network="10.10.0.0/16" || pod_network=$net_arg

if [[ -z $ip_arg ]]; then
	ip_apiserver=$(ip r g 8.8.8.8 | sed -rn 's/.* src ([0-9.]+) .*$/\1/p')
else
	ip_apiserver=$ip_arg
fi

[[ -n $token_arg ]] && [[ -n $ca_arg ]] && [[ -n $ip_control_arg ]] && is_worker=1

# Is root?
userName=$(whoami)

if [[ $userName != "root" ]]; then
	echo "Need run as root"
	exit
fi

# Have memory?
totalMem=$(free -m | grep -E "^Mem: " | xargs | cut -d" " -f 2)

if [[ $totalMem -lt 1700 ]]; then
	echo "Need at least 1700MB memory ram"
	exit
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
apt -y install apt-transport-https curl bash-completion openssl

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

cat << EOF > /etc/apt/sources.list.d/kubernetes.list
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /
EOF

apt -y update
apt -y install kubelet kubeadm kubectl

apt-mark hold kubelet kubeadm kubectl

[[ -d /etc/apt/keyrings ]] || mkdir -m 755 /etc/apt/keyrings

# Install containerd
apt -y update
apt -y install apt-transport-https ca-certificates curl gnupg lsb-release

# Add Docker's official GPG key:
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add the repository to Apt sources:
cat << EOF > /etc/apt/sources.list.d/docker.list
deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable
EOF

apt -y update 
apt -y install containerd.io

# Config containerd
containerd config default > /etc/containerd/config.toml

sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# Config services
systemctl restart containerd
systemctl status containerd

systemctl enable --now kubelet

# Config bash completion
echo 'alias k=kubectl' >>~/.bashrc
echo 'complete -o default -F __start_kubectl k' >>~/.bashrc
source ~/.bashrc

if [[ $is_worker ]]; then
	echo "kubeadm join $ip_control_arg --token $token_arg --discovery-token-ca-cert-hash $ca_arg"
	kubeadm join $ip_control_arg --token $token_arg --discovery-token-ca-cert-hash $ca_arg
else
	# Start control pane
	echo "kubeadm init --pod-network-cidr=$pod_network --apiserver-advertise-address=$ip_apiserver"
	kubeadm init --pod-network-cidr=$pod_network --apiserver-advertise-address=$ip_apiserver

	# Config kubeadm
	mkdir -p $HOME/.kube
	cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
	chown $(id -u):$(id -g) $HOME/.kube/config

	# Mount command to worker joint
	hash_arg=$(openssl x509 -in /etc/kubernetes/pki/ca.crt -noout -pubkey | openssl rsa -pubin -outform DER 2>/dev/null | sha256sum | cut -d' ' -f1)
	token_arg=$(kubeadm token list | grep -Eo "^[a-z0-9.]+")
	echo "### Start your worker ###"
	echo "curl -fSsl https://raw.githubusercontent.com/vinycarvalho/vwrk-tools/main/k8s-aws-install.sh | bash -s -- -a $ip_apiserver:6443 -t $token_arg -c sha256:$hash_arg"
	echo "#########################"

	while true; do
		node_lines=$(kubectl get node 2>&- | wc -l)
		if [[ $node_lines -gt 2 ]]; then
			kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml
			break
		else
			sleep 5
		fi
	done

fi


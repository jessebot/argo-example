#!/usr/bin/env
# By Max and Jesse

# install docker/kubectl deps
sudo apt-get -y install \
	apt-transport-https \
	ca-certificates \
	curl \
	gnupg-agent \
	software-properties-common

# download the gpg keys we need 
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
curl https://baltocdn.com/helm/signing.asc | sudo apt-key add -

# Add the repositories 
# Docker requires the appropriate ubuntu flavor for docker, in this case "focal".
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable"
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
echo "deb https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list

# update the package cache 
sudo apt-get -y update

# actually install something :D
sudo apt-get -y install \
	docker-ce \
	docker-ce-cli \
	containerd.io \
	kubectl \
	helm

# create a group for docker, and add the user to it for sudoless docker
sudo apt-get -y update
groupadd docker
sudo usermod -aG docker $USER
newgrp docker

# install KIND
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.13.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/bin/kind

# install ArgoCD CLI
sudo curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo chmod +x /usr/local/bin/argocd

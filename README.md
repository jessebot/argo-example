# ArgoCD and Vault on K8s
Just a quick example of how to set up a test Kuberentes (k8s) environment with KIND, and then use ArgoCD for k8s config management and then we'll also setup bitnami's sealed secret for you (This will allow you to encrypt secrets so they are safe for git checkin) :) In the future, we'll support other secret solutions, but as this is geared towards a homelab, at this time, we won't be supporting Vault, as to be secure, and match production, we'd need a multinode cluster, which is not always feasible for smaller labs. 

## Tech stack
| App/Tool | Reason |
|:--------:|:-------|
| [Docker](https://www.docker.com/get-started/)         | for the containers |
| [KIND](https://kind.sigs.k8s.io/)                     |  Tool to spin up a [Kubernetes](https://kubernetes.io/docs/concepts/overview/what-is-kubernetes/) [CLUSTER](media/peridot.png) in Docker, which we use to scale containers :3 |
| [helm2/helm3](https://helm.sh/docs/intro/quickstart/) | installs k8s apps (mostly a bunch of k8s yamls) |
| [ArgoCD](https://argo-cd.readthedocs.io/en/stable/)   | Continuous Delivery for k8s, from within k8s |
| [sealed-secrets](https://github.com/bitnami-labs/sealed-secrets) | generation of secrets as encrypted blobs so you can check secrets into git |


## Pre-Requisites
- [brew](https://brew.sh/) - Missing package manager for Mac (also supports Linux)

<details>
  <summary>macOS</summary>

  Make sure you have the [`Brewfile`](./deps/Brewfile) from this repo and then run:

  ```bash
    # MacOS only
    brew bundle install deps/Brewfile
  ```

</details>

<details>
  <summary>Linux</summary>

  ### LinuxBrew

  ```bash
  # Linux only
  brew bundle install deps/Brewfile_linux
  ```
  
  ### apt (On Debian distros)

  ```bash
  # Debian based distros only
  .deps/apt_dep_installation.sh
  ```

</details>

# Installation
Create a kubernetes cluster. If you don't have one, expand and follow the "Create a KIND Cluster" section.
<details>
  <summary>Create a KIND Cluster</summary>

  This is from the README.md for KIND in my other repo:
  [https://github.com/jessebot/smol_k8s_homelab/main/kind/](https://www.pfsense.org/products/#requirements)
  
  Create a quick small "ingress ready" KIND cluster with the below commands. 
  It will create a cluster called kind, and it will have one node, but it will
  be fast, like no more than a few minutes.
  
  ```bash
    cat <<EOF | kind create cluster --config=-
    kind: Cluster
    apiVersion: kind.x-k8s.io/v1alpha4
    nodes:
    - role: control-plane
      kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
      extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
    EOF
  ```
  
  Then install the nginx-ingress controller so you can access webpages from outside the cluster:
  ```bash
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
  ```
  
  You'll want to follow kind's advice and get some important info with, as well as verify the cluster is good to go:
  ``` bash
    kubectl cluster-info --context kind-kind
    kind get clusters
  ```
  Those commands should output this:
  ```bash
    Kubernetes control plane is running at https://127.0.0.1:64067
    CoreDNS is running at https://127.0.0.1:64067/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
  
    kind
  ```

</details>

<details>
  <summary>*Optional*: Install cert-manager</summary>

  ```bash
    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    helm install cert-manager jetstack/cert-manager \
        --namespace kube-system \
        --version v1.9.1 \
        --set installCRDs=true 
  ```
  
  Wait on cert-manager to deploy:

  ```bash
    kubectl rollout status -n kube-system deployment/cert-manager
    
    kubectl rollout status -n kube-system deployment/cert-manager-webhook
    
    kubectl wait --namespace kube-system \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/name=cert-manager \
      --timeout=90s
    
    kubectl wait --namespace kube-system \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/component=webhook \
      --timeout=90s
  ```

  After you've confirmed via `k9s` or `kubectl get pods -A` that all the
  cert-manager pods are completely ready, you can Deploy the lets-encrypt
  staging cluster issuer:

  ```bash
    cat <<EOF | kubectl apply -f -
    apiVersion: cert-manager.io/v1
    kind: ClusterIssuer
    metadata:
      name: letsencrypt-staging
    spec:
      acme:
        email: $EMAIL
        server: https://acme-staging-v02.api.letsencrypt.org/directory
        privateKeySecretRef:
          name: letsencrypt-staging
        solvers:
          - http01:
              ingress:
                class: nginx
    EOF
  ```

</details>

Now that we've verified we have a local k8s cluster, let's get Argo and Vault up and running!

## ArgoCD

### Helm Installation
We'll be installing the [argo-helm repo argo-cd chart](https://github.com/argoproj/argo-helm/blob/master/charts/argo-cd/)
Run the following helm commands to install the charts:

```bash
helm repo add argo-cd https://argoproj.github.io/argo-helm
helm dep update charts/argo-cd/
echo "charts/" > charts/argo-cd/.gitignore
```

Which should return something like this:

```
"argo-cd" has been added to your repositories

Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "argo" chart repository
Update Complete. ⎈Happy Helming!⎈
Saving 1 charts
Downloading argo-cd from repo https://argoproj.github.io/argo-helm
Deleting outdated charts
```

The next thing you need to do do is install the chart with:
```bash
helm install -n argo-cd argo-cd charts/argo/
```

## Argo CD with Vault (Kustomize Install)
Old, not recently tested.
```bash
# Create a Directory to Store the yamls
mkdir kustomize && cd kustomize

# Download all the graciously provided - can also use curl
wget https://raw.githubusercontent.com/argoproj-labs/argocd-vault-plugin/main/manifests/argocd-cm.yaml
wget https://raw.githubusercontent.com/argoproj-labs/argocd-vault-plugin/main/manifests/argocd-repo-server-deploy.yaml
wget https://raw.githubusercontent.com/argoproj-labs/argocd-vault-plugin/main/manifests/kustomization.yaml

# go up one dir
cd ..

# apply the kustomize files
k apply -k kustomize
```


### How to fix crd-install issue (Skip if no issue on `helm install`)
*Why and How*
You would see this:
```bash
$ helm install argo-cd charts/argo/
manifest_sorter.go:192: info: skipping unknown hook: "crd-install"
manifest_sorter.go:192: info: skipping unknown hook: "crd-install"
NAME: argo-cd
LAST DEPLOYED: Wed May 11 10:53:55 2022
NAMESPACE: default
STATUS: deployed
REVISION: 1
TEST SUITE: None
```

You need those CRDs, or the pod will just crash loop, and then when you try to follow the next logical step of port-forwarding to test the frontend, you'll get something like this, when you actually test it:
```bash
$ kubectl port-forward svc/argo-cd-argocd-server 8080:443
Forwarding from 127.0.0.1:8080 -> 8080
Forwarding from [::1]:8080 -> 8080
Handling connection for 8080
```

Which seems fine, but when you go to http://localhost:8080 in your browser you'll see this in stdout in your terminal:
```
E0511 11:07:43.094956   46063 portforward.go:406] an error occurred forwarding 8080 -> 8080: error forwarding port 8080 to pod 53c2b12a3c748bb2c9acd763ed898c5261227ca4b359c047ec264608cbc67058, uid : failed to execute portforward in network namespace "/var/run/netns/cni-84865981-c6a2-6e6d-1ce1-336602591e41": failed to connect to localhost:8080 inside namespace "53c2b12a3c748bb2c9acd763ed898c5261227ca4b359c047ec264608cbc67058", IPv4: dial tcp4 127.0.0.1:8080: connect: connection refused IPv6 dial tcp6 [::1]:8080: connect: connection refused
E0511 11:07:43.095553   46063 portforward.go:234] lost connection to pod
Handling connection for 8080
E0511 11:07:43.096354   46063 portforward.go:346] error creating error stream for port 8080 -> 8080: EOF
```

This happens because you're using an older version of argoCD, and is apparently because of [this issue](https://github.com/bitnami/charts/issues/7972) and is fixed by [this](https://github.com/helm/helm/issues/6930), so you can just update your version.

*Fix*
Update `version` of your `charts/argo/Chart.yaml` to at least 4.6.0 (cause that's what worked for me :D)

Then you'll need to rerun the dep update:
```bash
helm dep update charts/argo/
```

Followed by uninstalling, and then reinstalling:
```bash
$ helm uninstall argo-cd
release "argo-cd" uninstalled
```

### Resume here after CRD issue detour
Now, for the perfect installation of our dreams:
```bash
$ helm install argo-cd charts/argo/
NAME: argo-cd
LAST DEPLOYED: Wed May 11 14:52:59 2022
NAMESPACE: default
STATUS: deployed
REVISION: 1
TEST SUITE: None
```
:chef-kiss:

## Argo via the GUI
You'll need to test out the front end, but before you can do that, you need to do some port forwarding:
```bash
# Do this one if you didn't install ArgoCD with Vault
$ kubectl port-forward svc/argo-cd-argocd-server 8080:443
Forwarding from 127.0.0.1:8080 -> 8080
Forwarding from [::1]:8080 -> 8080
Handling connection for 8080
```
or
```bash
# Do this if you installed ArgoCD WITH Vault
$ kubectl port-forward svc/argocd-server 8080:443
Forwarding from 127.0.0.1:8080 -> 8080
Forwarding from [::1]:8080 -> 8080
Handling connection for 8080
```

SUCCESS, we now get this in the browser:

<img src="media/argo_screenshot_2022-05-11_15.36.20.png" alt="Screenshot of the self-hosted-k8s ArgoCD login page in firefox" width="500"/>

You can now login with the default username, `admin`, and auto-generated password from this k8s secret:
```bash
kubectl get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### CLI
First you should generate cli completion for your shell of choice. In my case, it was BASH:
```bash
$ argocd completion bash > ~/.bashrc_argocd
$ source ~/.bashrc_argocd

# need to port forward, but we want this in the background
$ kubectl port-forward svc/argo-cd-argocd-server 8080:443 &
```

You'll need to make sure you have your argo CD server address set with:
```bash
# create the default config location:
$ mkdir -p ~/.config/argocd/config
```

# Notes
Still interested in Vault with ArgoCD? Check out the following:
- [ArgoCD Vault Plugin](https://argocd-vault-plugin.readthedocs.io/en/stable/installation/) - ArgoCD with Vault
- [ArgoCD Vault Replacer](https://github.com/crumbhole/argocd-vault-replacer) - for replacing secrets with vault values

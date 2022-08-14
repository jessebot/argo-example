# ArgoCD on K8s (now with secrets)
Just a quick example of how to set up a test Kuberentes (k8s) environment with KIND, and then use ArgoCD for k8s config management and then we'll also setup bitnami's sealed secret for you (This will allow you to encrypt secrets so they are safe for git checkin) :) In the future, we'll support other secret solutions, but as this is geared towards a homelab, at this time, we won't be supporting Vault, as to be secure, and match production, we'd need a multinode cluster, which is not always feasible for smaller labs. 

## Tech stack
| App/Tool | Reason |
|:--------:|:-------|
| [Docker](https://www.docker.com/get-started/)         | for the containers |
| [KIND](https://kind.sigs.k8s.io/)                     |  Tool to spin up a [Kubernetes](https://kubernetes.io/docs/concepts/overview/what-is-kubernetes/) [CLUSTER](media/peridot.png) in Docker, which we use to scale containers :3 |
| [helm2/helm3](https://helm.sh/docs/intro/quickstart/) | installs k8s apps (mostly a bunch of k8s yamls) |
| [Argo CD](https://argo-cd.readthedocs.io/en/stable/)   | Continuous Delivery for k8s, from within k8s |
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

  Make sure you have the [`Brewfile_linux`](./deps/Brewfile_linux) from this repo and then run:

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

  This is from the my other homelab repo, [smol_k8s_homelab](https://github.com/jessebot/smol_k8s_homelab/),
  and will install KIND with the proper ingress controller resources as well as metallb so you can locally route your install :) 

  ```bash
    # You can look at exactly what this does in https://raw.githubusercontent.com/jessebot/smol_k8s_homelab/main/kind/README.md
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jessebot/smol_k8s_homelab/main/kind/bash_full_quickstart.sh)"

    # tip: use :quit to exit k9s, you can also use :q similar to vim
  ```

</details>

Now that we have a local k8s cluster, let's get Argo and Bitnami Sealed Secrets up and running!

## Sealed Secrets
This is a Bitnami project, so we'll need to first add their helm chart repo:
```bash
helm repo add https://bitnami-labs.github.io/sealed-secrets
helm repo update
```

Then you can install the helm chart like this:
```bash
helm install sealed-secrets -n sealed-secrets --create-namespace --set namespace="sealed-secrets" sealed-secrets/sealed-secrets
```

That's it :D Onto argocd~!

## ArgoCD
We'll be installing the [argo-helm repo argo-cd chart](https://github.com/argoproj/argo-helm/blob/master/charts/argo-cd/).
Run the following helm commands to add the helm repo first:

```bash
# add the repo and update
helm repo add argo-cd https://argoproj.github.io/argo-helm
helm repo update
```

Next, go into `values.yml` in this repo and change line 10 from `selfhosting4dogs.com` to a domain of your choosing :)
```yaml
   hosts:
     - "argocd.selfhosting4dogs.com"
```

The next thing you need to do do is install the chart with:
```bash
helm install argocd argo-cd/argo-cd -n argocd --create-namespace --values values.yml
```

## Argo via the GUI
Assuming this is a local homelab setup, you'll need to either go into your router and update your DNS or you can update your `/etc/hosts` file to route this to the local IP of this cluster. For example, here's my `/etc/hosts`:

```
127.0.0.1       localhost argocd.selfhosting4dogs.com
```

Then, you should be able to go to http://argocd.selfhosting4dogs.com in a browser.

You can now login with the default username, `admin`, and auto-generated password from this k8s secret:
```bash
kubectl get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" -n argo-cd | base64 -d
```

## Argo via the CLI
First you should generate cli completion for your shell of choice. In my case, it was BASH:
```bash
argocd completion bash > ~/.bashrc_argocd
source ~/.bashrc_argocd
```

Grab the exact host from the output of the checking the ingress:
```bash
kubectl get ing -A
NAMESPACE   NAME                    CLASS   HOSTS                           ADDRESS      PORTS    AGE
argocd      argo-cd-argocd-server   nginx   argocd.selfhosting4dogs.com   192.168.72.22   80      31s
```

Get your password here.
```bash
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

This you should be able to login like so:
```bash
  argocd login --username admin --password mysupercoolplaintextpassword argocd.selfhosting4dogs.com --grpc-web
```

Which should return something like this:
```
'admin:login' logged in successfully
Context 'argocd.selfhosting4dogs.com' updated
```

Now you can do things like this, checking your active argocd repos:
```
argocd repo list --grpc-web
```

### Adding an Application example
Let's try an easy one first :) We'll use my [example prometheus repo](https://github.com/jessebot/prometheus_example) get your monitoring working in this cluster:

```bash
# this adds the repo as something argo CD has access to
argocd repo add https://github.com/jessebot/prometheus_example

# This creates the app, and the namespace it will live in
argocd app create prometheus --repo https://github.com/jessebot/prometheus_example.git --dest-namespace monitoring --dest-server https://kubernetes.default.svc --path . --sync-policy auto --sync-option CreateNamespace=true
```

### Now for an example with a sealed secret
Coming soon. Working on a fancy repo to demo this with nextcloud :D

# Cleanup
To delete the kind cluster:
```bash
kind delete cluster
```

To just uninstall everything we installed for argocd and sealed secrets:
```bash
helm uninstall argo-cd -n argocd
helm uninstall sealed-secrets -n sealed-secrets
```

# Notes

## Troubleshooting
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

## Other Tips

Wanna have argo manage itself? Check out [Arthur's guide](https://www.arthurkoziel.com/setting-up-argocd-with-helm/), which I found really helpful.

Still interested in Vault with ArgoCD? Check out the following:
- [ArgoCD Vault Plugin](https://argocd-vault-plugin.readthedocs.io/en/stable/installation/) - ArgoCD with Vault
- [ArgoCD Vault Replacer](https://github.com/crumbhole/argocd-vault-replacer) - for replacing secrets with vault values

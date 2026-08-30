# Cluster bootstrap

This repository assumes that the Kubernetes cluster and Argo CD are installed
outside the GitOps reconciliation flow. The repository begins at the Argo CD
root Application.

## Local test cluster

The current test setup uses `kind` with the default CNI disabled so Cilium can
be installed as the cluster CNI.

```powershell
kind create cluster --name cilium-gitops-test --config .\kind-config.yaml
cilium install --version <CILIUM_VERSION>
cilium status --wait
```

The kind configuration must include:

```yaml
networking:
  disableDefaultCNI: true
```

The exact Cilium version should match the version used for the test cluster.
Do not apply the GitOps network policies before Cilium is ready.

## Install Argo CD

Install Argo CD with the official manifest or the installation method used by
the target cluster. Then apply the repository's one-time root Application:

```powershell
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -f .\bootstrap\argocd-root.yaml
```

`bootstrap/argocd-root.yaml` points Argo CD at the selected Git branch and
recursively loads the manifests under `argocd/`. After this step, Argo CD
creates the AppProjects, Applications, and ApplicationSets from Git.

## Branch selection

The active environment points to `main` in the bootstrap and ApplicationSet
manifests. The protected `feature/clean-gitops-layout` branch remains available
for review but is not used as the cluster source.

The cluster bootstrap file is intentionally kept separate from the Argo CD
managed application tree. It is applied once by an operator or an external
provisioning script; Argo CD manages the resources below it afterwards.

## Verification

```powershell
kubectl get applications -n argocd
kubectl get applicationsets -n argocd
kubectl get pods -A
```

The GitLab CI validation jobs do not need access to this cluster. They render
the Kustomize workloads and validate raw YAML. Only Argo CD and the Sealed
Secrets Controller require cluster access.

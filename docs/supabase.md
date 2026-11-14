# Supabase GitOps deployments

Supabase is managed in both Kubernetes clusters:

- The on-prem cluster receives the Applications under
  `clusters/onprem/argocd/applications/` through the repository's normal root Application. Its
  default storage class is `standard`, and Cilium egress policies are managed
  with the other platform policies.
- The single-node OCI Osaka K3s cluster receives the Applications under
  `clusters/oci-osaka/argocd/` through its separate root Application. It uses
  `local-path` storage on the instance's boot disk and pins Pods to ARM64 nodes.

Both clusters use the community Kubernetes Operator and matching chart version
`0.8.4`. Supabase's [self-hosting documentation](https://supabase.com/docs/guides/self-hosting)
recommends Docker and identifies Kubernetes as a community-maintained project.
The Operator is early-stage; review its upgrade notes before changing versions.

## On-prem cluster

Before reusing the on-prem cluster, apply
`bootstrap/argocd-onprem-root.yaml` once so its root Application reads
`clusters/onprem/argocd/`. After the change is merged to `main`, that root
Application discovers the Supabase Applications automatically. It installs
the Operator first and waits for its Application health before syncing the
project chart. The platform's Cilium policy permits API access from the
Operator, internal Supabase component traffic, and HTTP(S) egress from Edge
Functions.

## OCI Osaka K3s bootstrap

The OCI Argo CD instance must be able to read the private GitHub repository
before its root Application is applied. In that cluster's Argo CD UI, add
`https://github.com/lime985340/platform-gitops.git` under **Settings →
Repositories** using HTTPS and a GitHub credential with read access. Do not
commit the credential to this repository.

After this branch is merged to `main`, apply the OCI-specific root Application
once from a machine with access to the OCI cluster:

```sh
kubectl apply -f bootstrap/argocd-oci-osaka-root.yaml
```

That root loads only the OCI Argo CD settings, AppProject, and Supabase
Applications in `clusters/oci-osaka/argocd/`. It does not install the other
platform components or workloads.

## Shared configuration

- Operator and project charts are pinned to `0.8.4`. The Operator installs
  CRDs before the project chart is synced.
- Both deployments disable Analytics and Vector to reduce the initial
  footprint.
- Ingress is disabled. The Envoy Service remains internal. After installation,
  use `kubectl -n supabase port-forward svc/supabase-envoy 8000:8000` to open
  Studio and the API at `http://localhost:8000`.
- PostgreSQL requests `20Gi`, Storage requests `5Gi`, and Studio requests
  `1Gi`. The existing platform cluster uses `standard`; OCI uses K3s
  `local-path`. OCI claims share the node's boot disk rather than a separate
  block volume, and neither setup provides backups or high availability.
- OCI Pods use `kubernetes.io/arch: arm64`. Their chart-pinned images publish
  `linux/arm64` manifests; the container runtime selects the matching image
  from the normal image tags.
- The Operator creates database, Studio, and API credentials as Kubernetes
  Secrets. Keep their values out of Git and retrieve them from the `supabase`
  namespace when needed.

Self-hosting means the operator is responsible for security updates, database
maintenance, backups, recovery, monitoring, and uptime.

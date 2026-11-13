# Supabase on OCI Osaka K3s

This deployment is isolated from the repository's existing `argocd/` root. The
normal root Application points at `argocd/` and will not discover
`clusters/oci-osaka/argocd/`; the Supabase Applications below therefore target
the single-node OCI Osaka K3s cluster only.

Supabase is installed with the [community Kubernetes Operator](https://github.com/supabase-community/supabase-kubernetes).
Supabase's [self-hosting documentation](https://supabase.com/docs/guides/self-hosting)
recommends Docker and identifies Kubernetes as a community-maintained project.
The Operator is currently early-stage, so review its upgrade notes before
changing the pinned chart version.

## Bootstrap

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

That root loads only the OCI AppProject and Supabase Applications in
`clusters/oci-osaka/argocd/`. It does not install the repository's other
platform components or workloads.

## Configuration

- Operator and project charts are pinned to `0.8.4` and installed in separate
  sync waves so the CRDs are installed before the Supabase project.
- Analytics and Vector are disabled to reduce the initial footprint on the
  single-node server.
- Ingress is disabled. The Envoy Service remains internal; after installation,
  use `kubectl -n supabase port-forward svc/supabase-envoy 8000:8000` to open
  Studio and the API at `http://localhost:8000`.
- PostgreSQL requests `20Gi`, Storage requests `5Gi`, and Studio requests
  `1Gi`, using K3s `local-path` storage on the instance's existing boot disk.
  These claims share the node filesystem; they are not a separate OCI block
  volume and do not provide a backup or high-availability arrangement.
- The Operator creates database, Studio, and API credentials as Kubernetes
  Secrets. Keep their values out of Git and retrieve them from the `supabase`
  namespace when needed.

Self-hosting means the operator is responsible for security updates, database
maintenance, backups, recovery, monitoring, and uptime.

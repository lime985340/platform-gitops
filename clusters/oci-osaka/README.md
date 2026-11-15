# OCI Osaka workloads

OCI Osaka and on-prem are separate Kubernetes clusters. The workload tree under
`clusters/oci-osaka/workloads` mirrors the on-prem app and environment layout;
each cluster has its own Argo CD root, namespaces, Supabase projects, storage,
and Sealed Secrets. OCI-specific overlays keep the ARM64 image tags, local-path
storage, database service names, and ingress routes for this cluster.

The `workloads` ApplicationSet discovers every
`workloads/*/*/environments/*` directory. Adding an environment overlay there
creates an independent Argo CD Application in Osaka. `lime-game` and
`lime-mimir` are intentionally excluded.

Traefik runs in `kube-system`. The Cloudflare Quick Tunnel targets that
cluster-local Traefik service and routes to the same path-based app ingresses
as on-prem. Quick Tunnel hostnames are temporary and change when the tunnel is
recreated.

CLI Proxy API stores OAuth sessions on a cluster-local PVC. Osaka's dev and
prod instances need their own device login; they do not share on-prem or each
other's session data.

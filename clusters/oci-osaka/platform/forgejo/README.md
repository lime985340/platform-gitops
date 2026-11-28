# Forgejo on OCI Osaka

Forgejo is managed by the `forgejo` Argo CD application in the `oci-platform`
project. The official Forgejo Helm chart is pinned to `17.3.3` (Forgejo
`15.0.12` LTS). The chart uses its rootless image and a single SQLite-backed
instance on the cluster's `local-path` storage class.

The Tailscale Ingress creates `https://forgejo.tail90ac67.ts.net/` for devices
in the tailnet. This Ingress has no Funnel annotation, so it is not exposed to
the public internet. Account registration is disabled; the chart creates the
initial `forgejo_admin` account and stores its generated password in the
`forgejo-admin` Secret in the `forgejo` namespace. Retrieve it from the cluster
after the application is synced, then sign in and change the password.

Forgejo Actions is enabled, but no runner is deployed by this application.
Runners execute repository code and need a separately isolated runtime. Before
registering a runner, scope its registration to the intended repository and
avoid privileged access to the Kubernetes node or container runtime.

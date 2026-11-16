# OCI Osaka Tailscale Funnel

This change adds Tailscale Operator and one public Funnel hostname to the OCI
Osaka cluster. The Funnel hostname uses the tailnet's own `*.ts.net` domain
and forwards to the existing Traefik Service in `kube-system`.

## Public routes

The Funnel Ingress exposes the production application prefixes already routed
by Traefik:

| Public path | Application |
| --- | --- |
| `/atmo` | Atmo |
| `/saerom` | Q-Interior |
| `/neople` | Neople Game Analytics |
| `/ontology-asal-agent` | Ontology ASAL Agent |

Each prefix includes the app's browser-facing API routes beneath it. Funnel is
public Internet access: anyone who knows the hostname can reach these paths.
Supabase, its Studio and database, Argo CD, development routes, and unrelated
Services are not included. Cloudflare Quick Tunnel remains configured as-is.

The hostname is `oci-web.<tailnet>.ts.net`; Tailscale assigns the tailnet
suffix when the Funnel Ingress is created. This manifest does not add a
custom-domain alias.

## Tailscale prerequisites

1. MagicDNS and HTTPS certificates are enabled for `tail90ac67.ts.net`. Tailscale warns that the tailnet DNS name and machine names used in certificates are published in the public Certificate Transparency ledger; the new `oci-web` name will therefore be publicly discoverable.
2. Create a dedicated OAuth client scoped to `tag:k8s-operator` with the
   Operator's required write permissions for Services, Devices, and Auth Keys.
3. Add the tag ownership and Funnel permission to the tailnet policy. The
   Funnel grant is limited to proxy nodes tagged `tag:k8s`:
   ```json
   {
     "tagOwners": {
       "tag:k8s-operator": ["autogroup:admin"],
       "tag:k8s": ["tag:k8s-operator"]
     },
     "nodeAttrs": [
       {
         "target": ["tag:k8s"],
         "attr": ["funnel"]
       }
     ]
   }
   ```
   Merge these entries into the existing policy without replacing its other
   rules. This grants Funnel eligibility to nodes carrying `tag:k8s`; keep
   that tag limited to the Operator-created ingress proxy nodes.
4. Store a Secret Manager secret named `tailscale-operator` in the project
   selected by the repository's `GCP_PROJECT_ID` variable. Its latest version
   must be a JSON object with non-empty string fields `client_id` and
   `client_secret`. The GitHub Actions Workload Identity service account needs
   `secretmanager.versions.access` on that secret.
5. Run `Reseal workload secrets` from this feature branch with
   `secret_scope=tailscale-operator` and provide the OCI Osaka Sealed Secrets
   **public** certificate in `oci_sealed_secrets_cert`. The workflow reads the
   bundle, writes only the encrypted `sealed-secret.yaml` into this branch,
   and removes its temporary credential files.

Do not commit the OAuth secret values, the Secret Manager archive, or the
Sealed Secrets private key. The public certificate is needed for sealing but
does not decrypt the generated manifest.

## Deployment order and verification

The root Argo CD Application watches `main`, so the resources remain inactive
until the reviewed branch is merged. The Tailscale Operator Application installs
the chart and CRDs before the Funnel Application creates its Ingress.

After the cluster has been confirmed as the intended new OCI Osaka environment
and all prerequisites are ready, merge the reviewed changes. Verify the
Operator and proxy Pods, Argo CD `Synced/Healthy` state, and the assigned
`oci-web.<tailnet>.ts.net` address. Test the four application prefixes from
outside the tailnet. Do not enable Funnel on management, database, or
development endpoints.

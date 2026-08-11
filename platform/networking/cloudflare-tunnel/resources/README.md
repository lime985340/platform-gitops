# Cloudflare Quick Tunnel

This Deployment starts a temporary Cloudflare Quick Tunnel and proxies traffic to
the Traefik ClusterIP Service:

```text
http://traefik.traefik.svc.cluster.local:80
```

The generated `https://<random>.trycloudflare.com` URL is printed in the
`cloudflared` pod logs. It changes whenever the pod is recreated, so this is for
development and testing only. Quick Tunnels do not require a Cloudflare account,
DNS record, or tunnel token.

The current production and development workloads keep their host-based
Kubernetes Ingress rules. This directory also contains hostless Atmo dev preview
Ingress resources for the Quick Tunnel. A random Quick Tunnel hostname does not
automatically match hosts such as `argocd.lime.dedyn.io` or
`atmo-dev.lime.dedyn.io`.

## Handling the dynamic hostname

Quick Tunnel hostnames are temporary. The URL remains available while the
`cloudflared` process is running, but a pod or container restart creates a new
`https://<random>.trycloudflare.com` hostname. Do not write this URL to GitOps or
hard-code it in the web application.

For an Atmo preview, route the services by path with a hostless Ingress:

```text
https://<random>.trycloudflare.com/      -> atmo-web
https://<random>.trycloudflare.com/api  -> atmo-api
```

The browser-side web application must call the API with the relative path
`/api`, for example `fetch('/api/users')`. Because the web page and API use the
same current hostname, the API URL automatically follows the new Quick Tunnel
URL. The browser must not use a Kubernetes pod IP or a cluster-only Service DNS
name. Kubernetes Service DNS names are only suitable for server-side calls from
inside the cluster.

The fixed-domain Ingress resources for development or production can remain
unchanged. Create a separate preview Ingress without a `host` and without a
`tls` section; Cloudflare terminates HTTPS for the `trycloudflare.com` hostname,
so cert-manager does not need to issue a certificate for each new URL.

To find the current URL after a restart, inspect the pod logs:

```powershell
kubectl logs -n cloudflared deploy/cloudflared |
  Select-String "trycloudflare.com"
```

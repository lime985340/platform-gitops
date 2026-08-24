# Cloudflare Quick Tunnel

This Deployment starts a temporary Cloudflare Quick Tunnel and proxies traffic
to the Traefik ClusterIP Service:

```text
http://traefik.traefik.svc.cluster.local:80
```

The generated `https://<random>.trycloudflare.com` URL is printed in the
`cloudflared` pod logs. It changes whenever the pod is recreated, so this is
for development and testing only. Quick Tunnels do not require a Cloudflare
account, DNS record, custom domain, or tunnel token.

The hostless Ingress resources in the Atmo and Neople prod workload
Kustomizations route the random hostname by application prefix:

```text
https://<random>.trycloudflare.com/atmo       -> atmo-web-prod
https://<random>.trycloudflare.com/atmo/api   -> atmo-api-prod
https://<random>.trycloudflare.com/neople     -> neople-game-analytics-web-prod
```

The browser-side web application must call the API with the relative path
`/atmo/api`, for example `fetch('/atmo/api/v1/stations')`. Because the web page
and API use the same current hostname, the API URL automatically follows the
new Quick Tunnel URL. The browser must not use a Kubernetes pod IP or a
cluster-only Service DNS name.

There is no host or TLS section in the current prod Ingress resources. Cloudflare
terminates HTTPS for the temporary hostname, while `cloudflared` connects to
Traefik over the internal HTTP service.

The Cilium policy under `platform/policies` allows the tunnel's required
outbound TCP and UDP traffic on port `7844` to the Cloudflare edge.

To find the current URL after a restart, inspect the pod logs:

```powershell
kubectl logs -n cloudflared deploy/cloudflared |
  Select-String "trycloudflare.com"
```

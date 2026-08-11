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

The hostless preview Ingress resources in this directory route the random
hostname by path:

```text
https://<random>.trycloudflare.com/      -> atmo-web-dev
https://<random>.trycloudflare.com/api  -> atmo-api-dev
```

The browser-side web application must call the API with the relative path
`/api`, for example `fetch('/api/users')`. Because the web page and API use the
same current hostname, the API URL automatically follows the new Quick Tunnel
URL. The browser must not use a Kubernetes pod IP or a cluster-only Service
DNS name.

There is no host or TLS section in the preview Ingress resources. Cloudflare
terminates HTTPS for the temporary hostname, while `cloudflared` connects to
Traefik over the internal HTTP service.

To find the current URL after a restart, inspect the pod logs:

```powershell
kubectl logs -n cloudflared deploy/cloudflared |
  Select-String "trycloudflare.com"
```

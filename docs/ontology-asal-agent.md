# Ontology ASAL Agent

운영 보안, GraphDB 계정 분리, 실행 변수와 SealedSecret 절차는
[`ontology-asal-agent-security.md`](ontology-asal-agent-security.md)를 참조합니다.

The active cluster follows `main`, so this workload
is managed under `clusters/onprem/workloads/ontology-asal-agent/{api,web}/environments/{dev,prod}`.

## Current test flow

```text
GraphDB Helm Application
  -> asal-agent repository
  -> migration Job loads domain.ttl and shapes.ttl after GraphDB is reachable
  -> ontology agent API Deployment starts in triplestore mode
  -> the Web Deployment serves the static UI
  -> the prod route is exposed through Traefik

The service is split into API and Web workloads from the same application repository:

- `ontology-asal-agent-api` publishes `registry.gitlab.com/lime985340/ontology-asal-agent-api` for the API and migration Job.
- `ontology-asal-agent-web` publishes `registry.gitlab.com/lime985340/ontology-asal-agent-web`.
- `/ontology-asal-agent` routes to Web and `/ontology-asal-agent/api` routes to API.
```

The cluster Feature configuration routes the agent through the generic
`cli-proxy-api` workload. It uses the Proxy's OpenAI-compatible Chat Completions
endpoint and Codex OAuth credentials stored on the Proxy PVC. Cilium permits only
the matching ontology API environment to reach the Proxy; the API does not receive
a Proxy client key or the Codex OAuth token.

OpenRouter remains a local standalone fallback only. It is not the active
cluster configuration after the GitOps Feature is promoted.

The test cluster uses GraphDB without authentication so the data path can be
verified before the SealedSecret values are prepared. Until a valid
`graphdb.license` is sealed in the `graphdb` namespace and mounted by the
GraphDB chart. The migration Job does not duplicate that Secret into the API
namespace; it waits for GraphDB and relies on the server-side license when it
writes the ontology graphs. Without a valid license, the GraphDB write or
verification step fails instead of being silently skipped. The application is
configured with an explicit development-only local TTL fallback, so
`/api/health` is available while `/api/ready` remains 503 until the Proxy is
reachable and the ontology store is ready.

## Secret input

When the runtime values are ready, create separate GitLab File variables named
`ONTOLOGY_ASAL_AGENT_DEV_ENV` and `ONTOLOGY_ASAL_AGENT_PROD_ENV`, with one
`KEY=VALUE` per line:

```text
TRIPLESTORE_USERNAME=<reader username, when GraphDB security is enabled>
TRIPLESTORE_PASSWORD=<reader password, when GraphDB security is enabled>
```

The current Feature ConfigMap sets:

```text
LLM_PROVIDER=codex_proxy
LLM_BASE_URL=http://cli-proxy-api.<proxy-namespace>.svc.cluster.local:8317/v1
LLM_MODEL=<proxy model alias>
```

The GitOps sealing job encrypts only the API runtime values that still require a
Secret, such as GraphDB reader credentials, with the Sealed Secrets controller
certificate. Cilium policies in `clusters/onprem/platform/policies` provide the Proxy access
allow-list. The shared group registry variables continue to create
`gitlab-regcred` for both agent Namespaces.

For a protected environment, GraphDB bootstrap credentials must be sealed
separately from the agent runtime credentials. The agent receives only the
reader account; the ontology migration receives only the writer account. Neither
GraphDB administrator credentials nor plaintext values belong in Git.

The notification Gateway defaults to `local`, which records an approved draft in
the application outbox. To enable an external provider, set
`NOTIFICATION_GATEWAY=webhook` and `NOTIFICATION_WEBHOOK_URL` in the environment
ConfigMap, and provide `NOTIFICATION_WEBHOOK_API_KEY` through the workload Secret.
The provider must honor the `idempotency_key` sent in each delivery payload.

The Web deployment has no runtime application secret. It only uses the shared
GitLab registry pull credential generated for the Web namespace. The API keeps
its existing runtime Secret contract independently.

## URLs

```text
Agent Web route:    /ontology-asal-agent
Agent API route:    /ontology-asal-agent/api
GraphDB query URL:  http://graphdb.graphdb.svc.cluster.local:7200/repositories/asal-agent
GraphDB update URL: http://graphdb.graphdb.svc.cluster.local:7200/repositories/asal-agent/statements
```

The Web and API are separate Deployments. The Web container serves the React
build through Nginx, while the API Ingress owns only `/ontology-asal-agent/api`.
The Web uses the same browser origin and resolves API requests to that prefixed
path, so no cross-origin configuration is required.

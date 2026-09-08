# Ontology ASAL Agent

운영 보안, GraphDB 계정 분리, 실행 변수와 SealedSecret 절차는
[`ontology-asal-agent-security.md`](ontology-asal-agent-security.md)를 참조합니다.

The active cluster follows `main`, so this workload
is managed under `workloads/ontology-asal-agent/{api,web}/environments/{dev,prod}`.

## Current test flow

```text
GraphDB Helm Application
  -> asal-agent repository
  -> migration Job loads domain.ttl and shapes.ttl when a GraphDB license exists
  -> ontology agent API Deployment starts in triplestore mode
  -> the Web Deployment serves the static UI
  -> the prod route is exposed through Traefik

The service is split into API and Web workloads from the same application repository:

- `ontology-asal-agent` publishes `registry.gitlab.com/lime985340/ontology-asal-agent` for the API and migration Job.
- `ontology-asal-agent-web` publishes `registry.gitlab.com/lime985340/ontology-asal-agent-web`.
- `/ontology-asal-agent` routes to Web and `/ontology-asal-agent/api` routes to API.
```

The agent uses OpenRouter's OpenAI-compatible Chat Completions endpoint by
default. `openrouter/free` automatically selects an available free model. Free
models are suitable for portfolio demonstrations and development, but their
rate limits, latency, availability, and output quality can vary.

The test cluster uses GraphDB without authentication so the data path can be
verified before the SealedSecret values are prepared. Until a valid
`graphdb.license` is sealed, the repository can be listed but RDF queries and
writes fail with HTTP 500, so the migration Job skips cleanly. The application is configured with an explicit
development-only local TTL fallback, so `/api/health` is available while
`/api/ready` remains 503 until an LLM key is provided.

## Secret input

When the runtime values are ready, create separate GitLab File variables named
`ONTOLOGY_ASAL_AGENT_DEV_ENV` and `ONTOLOGY_ASAL_AGENT_PROD_ENV`, with one
`KEY=VALUE` per line:

```text
LLM_API_KEY=<OpenRouter API key>
TRIPLESTORE_USERNAME=<reader username, when GraphDB security is enabled>
TRIPLESTORE_PASSWORD=<reader password, when GraphDB security is enabled>
```

Create the OpenRouter key at <https://openrouter.ai/settings/keys>. The key is
used only by the API Deployment; it must not be placed in the Web image or
committed to Git. The current ConfigMap already sets:

```text
LLM_BASE_URL=https://openrouter.ai/api/v1/chat/completions
LLM_MODEL=openrouter/free
```

The GitOps sealing job encrypts this file with the Sealed Secrets controller
certificate and writes only encrypted data to
`workloads/ontology-asal-agent/api/environments/prod/sealed-secrets.yaml`.
The Dev variable writes to the corresponding `environments/dev` path. The shared
group registry variables continue to create `gitlab-regcred` for both agent
Namespaces.

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

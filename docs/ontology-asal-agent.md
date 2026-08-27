# Ontology ASAL Agent

The active test cluster follows `feature/clean-gitops-layout`, so this workload
is managed under `workloads/ontology-asal-agent/api/environments/prod`.

## Current test flow

```text
GraphDB Helm Application
  -> asal-agent repository
  -> migration Job loads domain.ttl and shapes.ttl
  -> ontology agent Deployment starts in triplestore mode
  -> Traefik exposes /ontology-asal-agent
```

The test cluster uses GraphDB without authentication so the data path can be
verified before the SealedSecret values are prepared. The application has no
LLM key initially, so `/api/health` is available while `/api/ready` remains 503.

## Secret input

When the runtime values are ready, create a GitLab File variable named
`ONTOLOGY_ASAL_AGENT_PROD_ENV` with one `KEY=VALUE` per line:

```text
LLM_API_KEY=<provider key>
TRIPLESTORE_USERNAME=<reader username, when GraphDB security is enabled>
TRIPLESTORE_PASSWORD=<reader password, when GraphDB security is enabled>
```

The GitOps sealing job encrypts this file with the Sealed Secrets controller
certificate and writes only encrypted data to
`workloads/ontology-asal-agent/api/environments/prod/sealed-secrets.yaml`.
The shared group registry variables continue to create `gitlab-regcred` for the
agent image.

For a protected environment, GraphDB bootstrap credentials must be sealed
separately from the agent runtime credentials. The agent receives only the
reader account; the ontology migration receives only the writer account. Neither
GraphDB administrator credentials nor plaintext values belong in Git.

## URLs

```text
Agent route:        /ontology-asal-agent
GraphDB query URL:  http://graphdb.graphdb.svc.cluster.local:7200/repositories/asal-agent
GraphDB update URL: http://graphdb.graphdb.svc.cluster.local:7200/repositories/asal-agent/statements
```

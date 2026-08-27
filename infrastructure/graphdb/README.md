# GraphDB for the Ontology ASAL Agent

This component deploys the official Ontotext GraphDB Helm chart through Argo CD.
The instance is internal-only (`ClusterIP`), persistent on `longhorn-2`, and starts
with one `asal-agent` repository.

## Runtime endpoint

The agent should use the repository-specific SPARQL query endpoint:

```text
http://graphdb.graphdb.svc.cluster.local:7200/repositories/asal-agent
```

The same URL is used for the agent's read-only `CONSTRUCT` requests. Ontology
publishing uses a separate migration/admin process and the repository's update
endpoint, not the agent Deployment.

## OpenBao secret contract

The ExternalSecret expects the following KV v2 record:

```text
kv/seed-ontology-asal-agent-graphdb
```

Required properties are:

```text
users.js             # GraphDB initial users.js document
GRAPHDB_AUTH_TOKEN   # base64(username:password) for the provisioner user
graphdb.license      # GraphDB license file contents
```

The `users.js` document must define the administrator and `graphdb-provisioner`
users with bcrypt password hashes. Do not commit that document or the token to
Git. The license is also kept only in OpenBao and mounted by the Helm chart. The
application reader credentials belong in a separate OpenBao record so
the agent never receives the GraphDB administrator/provisioner secret.

The GraphDB bootstrap secret is consumed once on first initialization. Rotating
`users.js` in OpenBao does not rewrite an already initialized GraphDB data volume;
user changes should be performed through the GraphDB administration workflow.

## Data loading

The repository is created by the Helm chart's post-install/post-upgrade hook. Load
`ontology/domain.ttl` into the ontology named graph and `ontology/shapes.ttl` into
the SHACL named graph with the application repository's migration script after the
GraphDB repository is ready.

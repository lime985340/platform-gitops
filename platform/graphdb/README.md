# GraphDB test deployment

The active `main` cluster uses the official Ontotext
GraphDB Helm chart through `argocd/applications/graphdb.yaml`.

The feature cluster intentionally starts with GraphDB security disabled so the
triplestore and ontology loading path can be verified before secret sealing. It
is an internal `ClusterIP` service with a persistent `standard` storage class.
GraphDB 11.5 still requires a valid license for repository transactions;
without `graphdb-license`, the repository can be listed but RDF `CONSTRUCT` and
ontology publishing requests return HTTP 500 in this test cluster. The Helm
values keep this Secret optional only for the initial test bootstrap.

When a license is available, configure `GRAPHDB_LICENSE_FILE` as a protected
GitLab File variable in the GitOps project and run the manual sealing job. The
pipeline writes only the encrypted `graphdb-license` SealedSecret to this
directory; the license contents never enter Git.
The repository endpoint is:

```text
http://graphdb.graphdb.svc.cluster.local:7200/repositories/asal-agent
```

For a protected environment, enable GraphDB security and provide a SealedSecret
containing the chart's initial `users.js` and provisioning Basic token. The
`graphdb.license` file must also be stored in the secret manager and mounted by
the chart. The
agent and ontology migration job must then use separate reader and writer
credentials. Those credentials must be generated through the GitOps Sealed
Secrets workflow and must not be committed as plaintext.

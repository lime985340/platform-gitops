# GraphDB test deployment

The active `feature/clean-gitops-layout` cluster uses the official Ontotext
GraphDB Helm chart through `argocd/applications/graphdb.yaml`.

The feature cluster intentionally starts with GraphDB security disabled so the
triplestore and ontology loading path can be verified before secret sealing. It
is an internal `ClusterIP` service with a persistent `standard` storage class.
The repository endpoint is:

```text
http://graphdb.graphdb.svc.cluster.local:7200/repositories/asal-agent
```

For a protected environment, enable GraphDB security and provide a SealedSecret
containing the chart's initial `users.js` and provisioning Basic token. The
agent and ontology migration job must then use separate reader and writer
credentials. Those credentials must be generated through the GitOps Sealed
Secrets workflow and must not be committed as plaintext.

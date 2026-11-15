# GraphDB in OCI Osaka

This is an independent GraphDB instance for Osaka's Ontology ASAL Agent apps.
The Argo CD Application uses Ontotext GraphDB 12.5.0 with a cluster-local
local-path volume and the same asal-agent repository configuration as on-prem.
The license SealedSecret is generated for Osaka by the oci-apps secret reseal
workflow; do not copy the on-prem ciphertext.

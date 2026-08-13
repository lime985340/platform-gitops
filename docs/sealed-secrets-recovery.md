# Sealed Secrets key backup and recovery

The Sealed Secrets Controller keeps the private sealing keys in Kubernetes
Secrets. The encrypted files in Git cannot be recovered after a cluster
rebuild unless the controller keys are restored first.

The backup contains private key material. Store it in an encrypted, access-
controlled backup location. Never commit it to GitLab, upload it as a normal
CI variable, or put it in a public artifact.

## Backup

Run this from an administrator workstation while the controller is running:

~~~powershell
kubectl get secret --namespace sealed-secrets --selector sealedsecrets.bitnami.com/sealed-secrets-key --output yaml | Set-Content -Encoding utf8 .\sealed-secrets-key-backup.yaml
~~~

Repeat the backup after the controller creates a new sealing key. The
Controller renews sealing keys periodically, so an old backup may not contain
the key used by newer SealedSecret resources.

## Recovery after cluster recreation

Install the Sealed Secrets Controller and wait until its namespace exists, but
restore the key backup before syncing workload SealedSecret resources:

~~~powershell
kubectl apply -f .\sealed-secrets-key-backup.yaml
kubectl rollout restart deployment/sealed-secrets-controller --namespace sealed-secrets
kubectl rollout status deployment/sealed-secrets-controller --namespace sealed-secrets
~~~

Then apply bootstrap/argocd-root.yaml or allow the existing root Application
to synchronize. The controller can now decrypt the existing encrypted values.

If the private key backup is unavailable, generate new application Secret
values, seal them with the new controller certificate, and rotate the old
credentials.

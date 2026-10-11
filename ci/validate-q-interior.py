import pathlib
import subprocess
import yaml

root = pathlib.Path(__file__).resolve().parent.parent
for workload in ("api", "web"):
    for environment in ("dev", "prod"):
        overlay = root / "workloads/q-interior" / workload / "environments" / environment
        documents = list(yaml.safe_load_all(subprocess.check_output(
            ["kubectl", "kustomize", str(overlay)], text=True
        )))
        resources = [d for d in documents if d]
        deployment = next(d for d in resources if d["kind"] == "Deployment")
        assert deployment["metadata"]["namespace"] == f"q-interior-{workload}-{environment}"
        assert all(d["kind"] != "Secret" for d in resources), "Plaintext secret is forbidden"
        assert not any(d["kind"] in ("Job", "CronJob") for d in resources), "Mobile deployment belongs to CI"
        pod = deployment["spec"]["template"]["spec"]
        assert pod["imagePullSecrets"] == [{"name": "gitlab-regcred"}]
        if deployment["spec"]["replicas"] > 0:
            sealed = [d for d in resources if d["kind"] == "SealedSecret"]
            assert any(d["metadata"]["name"] == "gitlab-regcred" for d in sealed)
            assert "bootstrap-pending" not in pod["containers"][0]["image"]
            if workload == "api":
                assert any(d["metadata"]["name"] == "q-interior-db-secret" for d in sealed)

template = yaml.safe_load((root / "ci/templates/q-interior-container.yml").read_text())
assert template[".q_gitops_trigger"]["trigger"]["forward"] == {
    "yaml_variables": False, "pipeline_variables": False
}, "Source variables must not override central secrets"
pipeline = yaml.safe_load((root / ".gitlab-ci.yml").read_text())
assert pipeline["spec"]["inputs"]["q_action"]["options"] == ["none", "deploy-api", "deploy-web"]
jobs = yaml.safe_load((root / "ci/q-interior-jobs.yml").read_text())
assert "q:android" not in jobs and "q:ios" not in jobs
assert "mobile" not in template["stages"], "Mobile builds belong to the client project CI"
assert not (root / "ci/q-interior-android.sh").exists()
assert not (root / "ci/q-interior-ios.sh").exists()

for environment in ("dev", "prod"):
    policy = yaml.safe_load((root / f"platform/policies/allow-q-interior-api-{environment}-mail-egress.yaml").read_text())
    assert policy["spec"]["endpointSelector"]["matchLabels"]["k8s:io.kubernetes.pod.namespace"] == f"q-interior-api-{environment}"
    mail = policy["spec"]["egress"][1]
    assert mail["toPorts"][0]["ports"] == [{"port": "587", "protocol": "TCP"}]
    assert "matchName" in mail["toFQDNs"][0] and "matchPattern" not in mail["toFQDNs"][0]

print("Q Interior manifest and pipeline boundaries: PASS")

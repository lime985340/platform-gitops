# Argo CD Bootstrap (C-2)

이 저장소는 **운영 대상(GitOps 대상) 리소스만** 포함합니다.

- `root-*.yaml`(App-of-Apps 루트 Application)은 **부트스트랩 단계(Ansible/Terraform)** 에서 1회 적용합니다.
- 이후 동기화/복구(self-heal)는 Argo CD가 이 저장소를 주기적으로 pull하여 수행합니다.

따라서 이 폴더에는 운영 중에 Argo CD가 지속 동기화할 리소스만 포함되며,
Argo CD 자체의 시드(seed) 리소스(루트 Application)는 저장소에 두지 않습니다.

# 다음 작업 계획

현재 GitOps 구성과 Sealed Secrets Controller 설치는 완료되어 있습니다.
다만 실제 서비스 Secret 값은 아직 입력하지 않았으므로 API와 Web workload는
`Degraded` 상태로 남아 있습니다. Secret 값 입력은 별도 작업으로 보류합니다.

## 보류한 작업

### 1. GitLab CI Variables 입력

다음 변수는 실제 값이 준비된 후 GitLab 프로젝트의 `Settings > CI/CD > Variables`
에서 등록합니다. Secret 값 자체는 이 문서나 Git에 기록하지 않습니다.

- `SEALED_SECRETS_CERT` - `kubeseal --fetch-cert`로 받은 공개 인증서, `File` 변수
- `GITLAB_REGISTRY_USERNAME` - 두 서비스 이미지에 접근하는 Registry username, 일반 `Variable`
- `GITLAB_REGISTRY_TOKEN` - 두 서비스 이미지에 `read_registry` 권한이 있는 token, 일반 `Variable`
- `ATMO_API_DEV_DB_ENV`
- `ATMO_API_DEV_JWT_ENV`
- `ATMO_API_DEV_OAUTH_ENV`
- `ATMO_API_DEV_PUBLICDATA_ENV`
- `ATMO_API_PROD_DB_ENV`
- `ATMO_API_PROD_JWT_ENV`
- `ATMO_API_PROD_OAUTH_ENV`
- `ATMO_API_PROD_PUBLICDATA_ENV`

이 GitOps 프로젝트의 sealing Job은 별도 Push token 대신 GitLab이 자동 제공하는
`CI_JOB_TOKEN`을 사용합니다. GitLab 프로젝트의 Job token repository push 허용
설정과 대상 Protected branch 정책이 맞아야 합니다. 서비스 저장소에서 이 저장소로
image tag를 Push하는 별도 흐름은 `GITOPS_PUSH_TOKEN`,
`GITOPS_PUSH_TOKEN_USER`, `GITOPS_BRANCH`를 계속 사용합니다.

변수의 실제 환경변수 형식과 예시는
[`secret-variables.md`](secret-variables.md)에 기록되어 있습니다. 공개 인증서 취득과
`SEALED_SECRETS_CERT` File 변수 등록은
[`sealed-secrets-certificate.md`](sealed-secrets-certificate.md)를 따릅니다.
Registry JSON이나 `auth` 값은 직접 만들지 않으며, CI가 username/token으로 생성합니다.

### 2. SealedSecret 생성 및 동기화

Secret 값을 입력한 뒤 다음 순서로 실행합니다.

1. GitLab에서 `New pipeline`을 선택합니다.
2. 대상 브랜치로 `feature/clean-gitops-layout`을 선택합니다.
3. Pipeline 변수 `UPDATE_SECRETS=true`를 추가합니다.
4. 수동 Job `seal:workload-secrets`를 실행합니다.
5. CI가 `kubeseal`로 암호화된 YAML을 생성하고 현재 브랜치에 Push합니다.
6. Argo CD가 변경사항을 동기화하는지 확인합니다.

`Protected` 변수를 사용할 경우 이 대상 브랜치가 GitLab의 Protected ref여야
합니다. 그렇지 않으면 변수는 Job에 전달되지 않습니다. Feature 브랜치를 보호하거나
Protected release 브랜치에서 이 작업을 실행하는 정책을 먼저 확정합니다.

생성되는 파일은 다음 네 개입니다.

```text
workloads/atmo/api/environments/dev/sealed-secrets.yaml
workloads/atmo/api/environments/prod/sealed-secrets.yaml
workloads/atmo/web/environments/dev/sealed-secrets.yaml
workloads/atmo/web/environments/prod/sealed-secrets.yaml
```

`encryptedData: {}` 상태의 파일은 임시 Placeholder이므로 운영 Secret으로
사용하지 않습니다.

### 3. Sealed Secrets 복구 훈련

Controller Private Key 백업은 Git 저장소 밖의 암호화되고 접근이 제한된 위치에
운영자가 별도로 생성하고 검증해야 합니다. 이 저장소는 백업 파일의 존재나 최신
상태를 보장하지 않습니다. 실제 클러스터 재구성 전에 백업 생성·복구 가능성을
별도 테스트 클러스터에서 확인합니다.

실제 클러스터 재구성 후 복구 훈련은 서비스 중단과 키 복원 절차를 확인할 수 있는
별도 테스트 클러스터에서 진행합니다. 상세 절차는
[`sealed-secrets-recovery.md`](sealed-secrets-recovery.md)를 참고합니다.

## 현재 진행하지 않는 작업

- 서비스 API/Web 저장소 CI 연동 코드는 각 저장소의
  `feature/clean-gitops-layout` 브랜치에 반영했습니다. 실제 Pipeline 실행을
  위해서는 각 서비스 저장소에 `GITOPS_PUSH_TOKEN`과
  `GITOPS_PUSH_TOKEN_USER`를 등록해야 합니다.
- Feature 브랜치 참조를 `main`으로 변경: Feature 브랜치 검증을 위해 현재 상태 유지
- 실제 Secret 값의 GitLab 등록: 값 준비 후 수동으로 진행
- 새 Registry 변수(`GITLAB_REGISTRY_USERNAME`, `GITLAB_REGISTRY_TOKEN`) 등록 후
  기존 `GITLAB_REGISTRY_DOCKER_CONFIG` placeholder는 별도 정리
- GitOps sealing Job은 `CI_JOB_TOKEN` repository push 설정이 필요하며, 현재
  프로젝트 설정을 확인한 뒤 Protected branch 정책을 별도로 결정
- Protected 변수는 Protected ref에서만 전달되므로, 현재 feature 브랜치에서
  사용할지 Protected branch 정책을 먼저 결정
- 기존 `GITOPS_PUSH_TOKEN`은 새 sealing 코드 배포와 수동 검증이 끝난 뒤에만 삭제
  (서비스 저장소의 별도 image update token은 유지)
- 서비스 저장소의 image update CI에는 `GITOPS_PUSH_TOKEN`과
  `GITOPS_PUSH_TOKEN_USER`가 모두 필요하며, `GITOPS_BRANCH`는 현재
  `feature/clean-gitops-layout`로 설정해야 함
- 실제 atmo-api OAuth 값은 `secret-variables.md`의 `KAKAO_*`, `GOOGLE_*`,
  `NAVER_*` 키 형식을 사용하고, atmo-web에는 OAuth client secret을 넣지 않음

Secret 값을 GitLab에 저장하는 것만으로는 파이프라인이 실행되지 않습니다. 실제
sealing은 모든 값과 Protected-ref 정책을 확인한 뒤 사용자가 수동으로 시작합니다.
Registry JSON과 `auth`는 CI가 생성하므로 사용자가 직접 만들지 않습니다.

## 완료 판단 기준

- `sealed-secrets` Application이 `Synced / Healthy`
- API/Web Application이 `Synced / Healthy`
- 모든 `SealedSecret`의 `encryptedData`가 실제 암호화 값으로 채워짐
- `gitlab-regcred` Secret이 정상 생성됨
- API/Web Pod가 Ready 상태가 됨

# 다음 작업 계획

현재 GitOps 구성과 Sealed Secrets Controller 설치는 완료되어 있습니다.
다만 실제 서비스 Secret 값은 아직 입력하지 않았으므로 API와 Web workload는
`Degraded` 상태로 남아 있습니다. Secret 값 입력은 별도 작업으로 보류합니다.

## 보류한 작업

### 1. GitLab CI Variables 입력

다음 변수는 실제 값이 준비된 후 GitLab 프로젝트의 `Settings > CI/CD > Variables`
에서 등록합니다. Secret 값 자체는 이 문서나 Git에 기록하지 않습니다.

- `SEALED_SECRETS_CERT` - `kubeseal --fetch-cert`로 받은 공개 인증서, `File` 변수
- `GITOPS_PUSH_TOKEN` - 현재 브랜치에 Push할 수 있는 GitLab 토큰
- `ATMO_API_DEV_DB_ENV`
- `ATMO_API_DEV_JWT_ENV`
- `ATMO_API_DEV_OAUTH_ENV`
- `ATMO_API_DEV_PUBLICDATA_ENV`
- `ATMO_API_PROD_DB_ENV`
- `ATMO_API_PROD_JWT_ENV`
- `ATMO_API_PROD_OAUTH_ENV`
- `ATMO_API_PROD_PUBLICDATA_ENV`
- `GITLAB_REGISTRY_DOCKER_CONFIG` - GitLab Container Registry Pull 인증 파일, `File` 변수

변수의 실제 환경변수 형식과 예시는
[`secret-variables.md`](secret-variables.md)에 기록되어 있습니다.

### 2. SealedSecret 생성 및 동기화

Secret 값을 입력한 뒤 다음 순서로 실행합니다.

1. GitLab에서 `New pipeline`을 선택합니다.
2. 대상 브랜치로 `feature/clean-gitops-layout`을 선택합니다.
3. Pipeline 변수 `UPDATE_SECRETS=true`를 추가합니다.
4. 수동 Job `seal:workload-secrets`를 실행합니다.
5. CI가 `kubeseal`로 암호화된 YAML을 생성하고 현재 브랜치에 Push합니다.
6. Argo CD가 변경사항을 동기화하는지 확인합니다.

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

Controller Private Key 백업은 Git 저장소 밖에 보관해야 합니다.
현재 백업 파일은 별도 로컬 경로에 생성했고, Git에 추가하지 않았습니다.

실제 클러스터 재구성 후 복구 훈련은 서비스 중단과 키 복원 절차를 확인할 수 있는
별도 테스트 클러스터에서 진행합니다. 상세 절차는
[`sealed-secrets-recovery.md`](sealed-secrets-recovery.md)를 참고합니다.

## 현재 진행하지 않는 작업

- 서비스 API/Web 저장소의 실제 CI 연동: 해당 서비스 저장소가 현재 작업 공간에 없어 보류
- Feature 브랜치 참조를 `main`으로 변경: Feature 브랜치 검증을 위해 현재 상태 유지
- 실제 Secret 값의 GitLab 등록: 값 준비 후 수동으로 진행

## 완료 판단 기준

- `sealed-secrets` Application이 `Synced / Healthy`
- API/Web Application이 `Synced / Healthy`
- 모든 `SealedSecret`의 `encryptedData`가 실제 암호화 값으로 채워짐
- `gitlab-regcred` Secret이 정상 생성됨
- API/Web Pod가 Ready 상태가 됨

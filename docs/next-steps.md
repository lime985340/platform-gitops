# 다음 작업 계획

현재 GitOps 구성과 Sealed Secrets Controller 설치는 완료되어 있습니다.
실제 운영 Secret이 아직 모두 봉인되지 않았다면 API/Web과 Worker 상태는
클러스터 동기화 결과에 따라 달라집니다. 임시 Neople API 키는 실제 키로
교체하기 전까지 운영 수집에 사용하지 않습니다.

## 보류한 작업

### 1. GitLab CI Variables 입력

다음 변수는 실제 값이 준비된 후 GitLab 프로젝트의 `Settings > CI/CD > Variables`
에서 등록합니다. Secret 값 자체는 이 문서나 Git에 기록하지 않습니다.

- `SEALED_SECRETS_CERT` - `kubeseal --fetch-cert`로 받은 공개 인증서, `File` 변수
- `GITLAB_REGISTRY_USERNAME` - 현재 `gitops` 프로젝트의 Registry username, 일반 `Variable`
- `GITLAB_REGISTRY_TOKEN` - 현재 `gitops` 프로젝트의 `read_registry` token, 일반 `Variable`
- `ATMO_API_DEV_DB_ENV`
- `ATMO_API_DEV_JWT_ENV`
- `ATMO_API_DEV_OAUTH_ENV`
- `ATMO_API_DEV_PUBLICDATA_ENV`
- `ATMO_API_PROD_DB_ENV`
- `ATMO_API_PROD_JWT_ENV`
- `ATMO_API_PROD_OAUTH_ENV`
- `ATMO_API_PROD_PUBLICDATA_ENV`
- `NEOPLE_GAME_ANALYTICS_API_DEV_ENV`
- `NEOPLE_GAME_ANALYTICS_API_PROD_ENV`

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

1. GitLab에서 `Build` → `Pipelines` → `New pipeline`을 선택합니다.
2. 대상 브랜치로 `main`을 선택합니다.
3. `Inputs`에서 boolean 입력 `update_secrets`를 `true`로 설정합니다.
4. Pipeline을 실행한 뒤 수동 Job `seal:workload-secrets`를 실행합니다.
5. CI가 `kubeseal`로 암호화된 YAML을 생성하고 현재 브랜치에 Push합니다.
6. Argo CD가 변경사항을 동기화하는지 확인합니다.

`update_secrets`는 root `.gitlab-ci.yml`의 `spec:inputs`로 선언된 입력입니다.
따라서 일반 Pipeline 변수 `UPDATE_SECRETS`를 추가하지 않으며, Secret 값도
Pipeline 입력 화면에 입력하지 않습니다. Inputs가 보이지 않는다면 최신
feature 브랜치의 CI 설정이 반영되었는지 확인합니다. Pipeline 변수 override
권한을 완화하는 방식으로 우회하지 않습니다.

기본값은 `false`이므로 입력을 `true`로 선택한 웹 Pipeline에서만 sealing Job이
생성됩니다. Push Pipeline에서는 생성되지 않습니다.

`Protected` 변수를 사용할 경우 이 대상 브랜치가 GitLab의 Protected ref여야
합니다. 그렇지 않으면 변수는 Job에 전달되지 않습니다. 현재 feature 브랜치는
sealing 실행을 위해 Protected로 관리합니다.

Sealing Job은 각 서비스의 환경별 `sealed-secrets.yaml`을 갱신합니다. Atmo의
대표 경로는 다음과 같고, Neople·Ontology 경로도 같은 방식으로 함께 갱신됩니다.

```text
workloads/atmo/api/environments/dev/sealed-secrets.yaml
workloads/atmo/api/environments/prod/sealed-secrets.yaml
workloads/atmo/web/environments/dev/sealed-secrets.yaml
workloads/atmo/web/environments/prod/sealed-secrets.yaml
workloads/neople-game-analytics/api/environments/dev/sealed-secrets.yaml
workloads/neople-game-analytics/api/environments/prod/sealed-secrets.yaml
workloads/neople-game-analytics/web/environments/dev/sealed-secrets.yaml
workloads/neople-game-analytics/web/environments/prod/sealed-secrets.yaml
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
  `main` 브랜치에 반영했습니다. 두 저장소는
  `lime985340` Group에서 상속한 `GITOPS_PUSH_TOKEN`,
  `GITOPS_PUSH_TOKEN_USER`, `GITOPS_BRANCH`를 사용합니다.
- GitOps 대상 브랜치를 `main`으로 변경했고 Group Variable도 `main`으로 설정했습니다.
- 임시 Neople Secret 값을 실제 API 키로 교체한 뒤 sealing 실행
- GitOps sealing Job은 `CI_JOB_TOKEN` repository push 설정과 Protected branch를
  사용하며, 서비스 image update용 Group token과 분리됩니다.
- 서비스 저장소의 image update CI에는 Group의
  `GITOPS_PUSH_TOKEN`, `GITOPS_PUSH_TOKEN_USER`, `GITOPS_BRANCH`가 필요하며,
  현재 `GITOPS_BRANCH`는 `main`으로 설정합니다.
- 기존 `GITLAB_REGISTRY_DOCKER_CONFIG`는 사용하지 않으며, Registry JSON과
  `auth`는 CI가 생성합니다.
- API release tag Pipeline을 사용할 때는 atmo-api의 `v*` Protected tag 정책도
  atmo-web과 일치하는지 확인합니다.
- 일반 Pipeline 변수 override 권한은 완화하지 않고 현재 `no_one_allowed` 정책을
  유지합니다.
- 실제 image update Pipeline은 서비스 코드가 변경되어 새 이미지를 만들 때만
  실행되며, 현재 GitOps에 기록된 image tag는 그대로 사용할 수 있습니다.
- Atmo 외부 경로는 `/atmo`, API 외부 경로는 `/atmo/api`를 사용합니다. Web 빌드
  변수 `VITE_API_BASE_URL`은 `/atmo/api/v1`로 설정합니다.
- Atmo OAuth Secret의 `KAKAO_REDIRECT_URI`, `GOOGLE_REDIRECT_URI`,
  `NAVER_REDIRECT_URI`에도 `/atmo/api/v1/auth/oauth/.../callback`을 사용하고,
  각 OAuth provider 콘솔에 같은 URL을 등록합니다.
- Atmo API의 Refresh Cookie 경로는 비밀값이 아닌 Deployment 설정
  `APP_AUTH_REFRESH_COOKIE_PATH=/atmo/api/v1/auth/refresh`로 관리합니다.
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

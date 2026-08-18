# GitLab Secret Variables 입력 가이드

이 저장소는 GitLab CI에서 Secret 값을 `kubeseal`로 암호화한 뒤, 암호화된
`SealedSecret` YAML만 Git에 커밋합니다. Argo CD는 이 YAML을 적용하고,
클러스터의 Sealed Secrets Controller가 Kubernetes Secret을 생성합니다.

실제 비밀번호·토큰·키·kubeconfig 내용은 이 문서와 Git 저장소에 넣지 않습니다.

## 사전 구성

클러스터에는 Sealed Secrets Controller가 설치되어 있어야 합니다. 현재 저장소는
`argocd/applications/sealed-secrets.yaml`의 Helm Chart Application으로 Controller를
관리합니다. Controller가 사용하는 Private Key는 클러스터 외부의 안전한 백업에도
보관해야 하며 Git에는 저장하지 않습니다.

로컬에서 처음 인증서를 가져올 때만 Kubernetes 접근이 필요합니다.

```bash
kubeseal --fetch-cert > sealed-secrets.crt
```

이후 `sealed-secrets.crt`는 공개 인증서이므로 GitLab의 File Variable로 등록해
CI에서 사용할 수 있습니다. 인증서가 갱신되면 다시 가져와 변수를 교체합니다.

## GitLab 변수 등록

GitLab 프로젝트에서 다음 메뉴로 이동합니다.

`Settings` → `CI/CD` → `Variables` → `Add variable`

다음 원칙으로 등록합니다.

- 여러 줄 값은 `Type: File`로 등록
- 운영 값은 `Protected`로 등록하고 실행 권한을 제한
- Secret 값은 `Masked` 또는 `Masked and hidden`을 사용
- 변수의 Value에는 파일 경로가 아니라 파일의 실제 내용을 입력
- `GITOPS_PUSH_TOKEN`은 대상 저장소에 `write_repository` 권한이 있는
  Project Access Token 또는 동일한 권한의 토큰으로 등록

## 필요한 변수

### `SEALED_SECRETS_CERT`

`kubeseal --fetch-cert`로 받은 Controller 공개 인증서 전체를 File 변수로
등록합니다. Private Key는 입력하지 않습니다.

### `GITOPS_PUSH_TOKEN`

CI가 생성한 암호화 YAML을 현재 Git 브랜치에 Push하기 위한 토큰입니다.
값을 로그나 문서에 출력하지 않습니다. Feature 브랜치에서 Protected 변수를
사용하려면 해당 브랜치가 보호되어 있어야 합니다.

### API DB/Redis

변수명:

- `ATMO_API_DEV_DB_ENV`
- `ATMO_API_PROD_DB_ENV`

```env
SPRING_DATASOURCE_URL=jdbc:postgresql://db.example.com:5432/atmo
SPRING_DATASOURCE_USERNAME=atmo
SPRING_DATASOURCE_PASSWORD=DB_PASSWORD
SPRING_REDIS_HOST=redis-master.redis.svc.cluster.local
SPRING_REDIS_PORT=6379
```

개발과 운영은 각각 별도 DB 값을 사용합니다.

### JWT

변수명:

- `ATMO_API_DEV_JWT_ENV`
- `ATMO_API_PROD_JWT_ENV`

```env
JWT_ACCESS_SECRET=JWT_ACCESS_SECRET_VALUE
JWT_REFRESH_SECRET=JWT_REFRESH_SECRET_VALUE
JWT_ACCESS_TTL_SECONDS=900
JWT_REFRESH_TTL_SECONDS=1209600
```

Access와 Refresh Secret은 서로 다른 충분히 긴 랜덤 값을 사용합니다.

### OAuth

변수명:

- `ATMO_API_DEV_OAUTH_ENV`
- `ATMO_API_PROD_OAUTH_ENV`

```env
KAKAO_CLIENT_ID=KAKAO_CLIENT_ID_VALUE
KAKAO_CLIENT_SECRET=KAKAO_CLIENT_SECRET_VALUE
KAKAO_REDIRECT_URI=https://YOUR_HOST/login/oauth2/code/kakao
KAKAO_AUTH_URI=https://kauth.kakao.com/oauth/authorize
KAKAO_TOKEN_URI=https://kauth.kakao.com/oauth/token
KAKAO_USERINFO_URI=https://kapi.kakao.com/v2/user/me
KAKAO_SCOPE=profile_nickname,account_email

GOOGLE_CLIENT_ID=GOOGLE_CLIENT_ID_VALUE
GOOGLE_CLIENT_SECRET=GOOGLE_CLIENT_SECRET_VALUE
GOOGLE_REDIRECT_URI=https://YOUR_HOST/login/oauth2/code/google
GOOGLE_AUTH_URI=https://accounts.google.com/o/oauth2/v2/auth
GOOGLE_TOKEN_URI=https://oauth2.googleapis.com/token
GOOGLE_USERINFO_URI=https://openidconnect.googleapis.com/v1/userinfo
GOOGLE_SCOPE=openid,profile,email

NAVER_CLIENT_ID=NAVER_CLIENT_ID_VALUE
NAVER_CLIENT_SECRET=NAVER_CLIENT_SECRET_VALUE
NAVER_REDIRECT_URI=https://YOUR_HOST/login/oauth2/code/naver
NAVER_AUTH_URI=https://nid.naver.com/oauth2.0/authorize
NAVER_TOKEN_URI=https://nid.naver.com/oauth2.0/token
NAVER_USERINFO_URI=https://openapi.naver.com/v1/nid/me
NAVER_SCOPE=name,email
```

### 공공데이터 API

변수명:

- `ATMO_API_DEV_PUBLICDATA_ENV`
- `ATMO_API_PROD_PUBLICDATA_ENV`

```env
PUBLIC_SERVICE_KEY=PUBLIC_DATA_SERVICE_KEY_VALUE
```

### GitLab Container Registry

변수명:

- `GITLAB_REGISTRY_USERNAME`
- `GITLAB_REGISTRY_TOKEN`

`registry.gitlab.com` private 이미지를 Pull할 수 있는 사용자명과 토큰을
일반 CI/CD 변수로 입력합니다. CI가 `kubectl create secret docker-registry`로
`gitlab-regcred` Secret을 생성한 뒤 SealedSecret으로 암호화합니다.

```text
GITLAB_REGISTRY_USERNAME=gitlab+deploy-token-123456
GITLAB_REGISTRY_TOKEN=DEPLOY_TOKEN_VALUE
```

Docker `config.json`을 직접 저장하지 않습니다.
Deploy Token에는 `read_registry` 권한만 부여하는 것을 권장합니다.

## 변수와 SealedSecret 매핑

| GitLab Variable | Namespace | SealedSecret |
| --- | --- | --- |
| `ATMO_API_DEV_DB_ENV` | `atmo-api-dev` | `atmo-db-secret` |
| `ATMO_API_DEV_JWT_ENV` | `atmo-api-dev` | `atmo-jwt-secret` |
| `ATMO_API_DEV_OAUTH_ENV` | `atmo-api-dev` | `atmo-oauth-secret` |
| `ATMO_API_DEV_PUBLICDATA_ENV` | `atmo-api-dev` | `atmo-publicdata-secret` |
| `ATMO_API_PROD_DB_ENV` | `atmo-api-prod` | `atmo-db-secret` |
| `ATMO_API_PROD_JWT_ENV` | `atmo-api-prod` | `atmo-jwt-secret` |
| `ATMO_API_PROD_OAUTH_ENV` | `atmo-api-prod` | `atmo-oauth-secret` |
| `ATMO_API_PROD_PUBLICDATA_ENV` | `atmo-api-prod` | `atmo-publicdata-secret` |
| `GITLAB_REGISTRY_USERNAME` + `GITLAB_REGISTRY_TOKEN` | Atmo API/Web 각 Namespace | `gitlab-regcred` |

생성되는 파일은 다음과 같습니다.

```text
workloads/atmo/api/environments/dev/sealed-secrets.yaml
workloads/atmo/api/environments/prod/sealed-secrets.yaml
workloads/atmo/web/environments/dev/sealed-secrets.yaml
workloads/atmo/web/environments/prod/sealed-secrets.yaml
```

파일 안에는 `encryptedData`만 저장되며 실제 값은 저장되지 않습니다.
SealedSecret의 이름과 Namespace는 암호화 시점과 적용 시점에 같아야 합니다.

## 동기화 실행

1. 위 GitLab 변수를 등록하거나 수정합니다.
2. `Build` → `Pipelines`에서 Pipeline을 실행합니다.
3. 수동 작업 `seal:workload-secrets`를 실행합니다.
4. CI가 `kubeseal`로 YAML을 생성하고 `[skip ci]` 커밋으로 현재 브랜치에 Push합니다.
5. Argo CD가 변경된 SealedSecret을 동기화합니다.
6. Controller가 일반 Kubernetes Secret을 생성하면 API/Web이 새 값을 사용합니다.

Secret 값을 변경할 때마다 Git 커밋이 생성됩니다. 애플리케이션이 값을 시작
시점에만 읽는다면 Secret 동기화 후 해당 Deployment를 재시작해야 합니다.

## Pipeline trigger

Normal pushes run the manifest validation jobs only. The Secret sealing job is
created only when starting a pipeline manually with the variable below:

```text
UPDATE_SECRETS=true
```

In GitLab, open `Build` → `Pipelines` → `New pipeline`, select the target
branch, add `UPDATE_SECRETS=true` as a pipeline variable, and run the pipeline.
Then start the `seal:workload-secrets` manual job. The generated commit uses
`[skip ci]`, so it does not create another pipeline.

## GitLab Runner

이 작업은 Kubernetes API에 접근하지 않고 공개 인증서로 암호화한 뒤 Git만
Push하므로 GitLab.com shared runner로 충분합니다. 따라서 현재 저장소에는
GitLab Runner Helm Chart나 Runner ServiceAccount를 추가하지 않습니다.

클러스터 내부 Runner는 다음과 같은 경우에만 별도로 검토합니다.

- GitLab.com에 접근할 수 없는 폐쇄망
- 전용 빌드 도구나 사설 네트워크가 필요한 경우
- CI Job을 클러스터 내부에서 실행해야 하는 정책이 있는 경우

Runner를 추가하더라도 SealedSecret 암호화에는 Kubernetes 권한을 부여하지
않는 것이 기본 원칙입니다.

## 보안 주의사항

- SealedSecret YAML의 `encryptedData`는 Git에 저장해도 되지만 실제 값은 넣지 않습니다.
- Controller Private Key와 Kubernetes Secret 백업은 Git에 저장하지 않습니다.
- `SEALED_SECRETS_CERT`에는 공개 인증서만 넣습니다.
- `.env`, Docker 인증 파일, kubeconfig, Token을 커밋하지 않습니다.
- Secret 값이나 Push Token을 CI 로그에 출력하지 않습니다.
- Controller Private Key를 잃으면 기존 SealedSecret을 복호화할 수 없으므로 안전하게 백업합니다.

# GitLab Secret Variables 입력 가이드

이 문서는 GitOps 저장소의 `sync:workload-secrets` 작업에 필요한 GitLab
CI/CD Variables의 입력 형식을 설명합니다. 실제 비밀번호, 토큰, 키, 인증서,
`kubeconfig` 내용은 이 문서나 Git 저장소에 넣지 않습니다.

## 1. GitLab에 변수 추가

GitLab 프로젝트에서 다음 메뉴로 이동합니다.

`Settings` → `CI/CD` → `Variables` → `Add variable`

각 변수는 다음 원칙으로 추가합니다.

- `Type`: `File`
- `Visibility`: 가능한 경우 `Masked` 또는 `Masked and hidden`
- 운영용 변수: `Protected`를 사용하고 실행 권한을 제한
- 변수의 `Value`에는 파일 경로가 아니라 파일의 실제 내용을 입력
- 변수명과 파일 내용의 키 이름은 아래 예시와 정확히 일치

`File` 변수는 CI 실행 시 임시 파일로 제공됩니다. `ci/sync-secrets.sh`는
그 임시 파일을 Kubernetes Secret으로 변환한 뒤 작업 종료 시 삭제합니다.

> Feature 브랜치에서 Protected 변수를 사용할 경우 해당 브랜치가 보호되어
> 있어야 합니다. 보호되지 않은 브랜치에서 운영 Secret을 사용할 필요가
> 있다면 먼저 브랜치 보호 정책을 확인하세요.

## 2. 클러스터 접속 변수

### `KUBECONFIG`

GitLab CI Runner가 접근할 수 있는 Kubernetes 클러스터의 kubeconfig 전체
내용을 `File` 변수로 입력합니다.

```yaml
apiVersion: v1
kind: Config
clusters:
  # 실제 클러스터 설정을 입력합니다.
contexts:
  # 실제 context 설정을 입력합니다.
current-context: your-context
users:
  # 실제 인증 설정을 입력합니다.
```

로컬 `kind` 클러스터는 일반적으로 GitLab.com shared runner에서 접근할 수
없습니다. 이 경우 CI 작업 대신 로컬에서 같은 `ci/sync-secrets.sh`를
실행하거나, Runner가 접근 가능한 클러스터와 제한된 ServiceAccount용
kubeconfig를 사용합니다. 광범위한 `cluster-admin` kubeconfig를 등록하지
않습니다.

## 3. Atmo API 환경 변수

개발과 운영은 같은 형식의 파일을 사용하지만 반드시 별도 변수로 등록합니다.

- 개발: `ATMO_API_DEV_*`
- 운영: `ATMO_API_PROD_*`

### DB 및 Redis

변수명:

- `ATMO_API_DEV_DB_ENV`
- `ATMO_API_PROD_DB_ENV`

값은 `KEY=value` 형식의 여러 줄 파일입니다.

```env
SPRING_DATASOURCE_URL=jdbc:postgresql://db.example.com:5432/atmo
SPRING_DATASOURCE_USERNAME=atmo
SPRING_DATASOURCE_PASSWORD=DB_PASSWORD
SPRING_REDIS_HOST=redis-master.redis.svc.cluster.local
SPRING_REDIS_PORT=6379
```

`SPRING_DATASOURCE_URL`, 사용자명, 비밀번호는 실제 DB 환경에 맞게 바꿉니다.
현재 GitOps의 Redis Service 이름은 `redis-master`이며 Namespace는 `redis`입니다.

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

Access와 Refresh Secret은 서로 다른 충분히 긴 랜덤 값을 사용합니다. TTL은
초 단위이며 애플리케이션 정책에 맞춰 설정합니다.

### OAuth

변수명:

- `ATMO_API_DEV_OAUTH_ENV`
- `ATMO_API_PROD_OAUTH_ENV`

각 공급자의 Client ID, Client Secret, callback URI와 OAuth endpoint를
모두 입력합니다.

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

`YOUR_HOST`는 실제 외부 접속 주소로 변경합니다. Quick Tunnel은 파드가
재생성될 때 `trycloudflare.com` 주소가 바뀔 수 있으므로 OAuth 공급자에
등록한 Redirect URI와 현재 주소가 일치해야 합니다. 고정 주소가 필요하면
Named Tunnel과 고정 도메인을 사용합니다.

### 공공데이터 API

변수명:

- `ATMO_API_DEV_PUBLICDATA_ENV`
- `ATMO_API_PROD_PUBLICDATA_ENV`

```env
PUBLIC_SERVICE_KEY=PUBLIC_DATA_SERVICE_KEY_VALUE
```

## 4. GitLab Container Registry 인증

변수명:

- `GITLAB_REGISTRY_DOCKER_CONFIG`

이 변수는 `registry.gitlab.com`에서 private 이미지를 받을 수 있는 Docker
`config.json` 전체 내용을 `File` 변수로 입력합니다.

```json
{
  "auths": {
    "registry.gitlab.com": {
      "username": "gitlab+deploy-token-123456",
      "password": "DEPLOY_TOKEN_VALUE",
      "auth": "BASE64_OF_USERNAME_COLON_TOKEN"
    }
  }
}
```

권장 방식은 GitLab Deploy Token을 만들고 `read_registry` 권한만 부여하는
것입니다. `auth` 값은 `username:token`을 Base64로 인코딩한 값이어야 하며,
실제 Token을 문서나 로그에 남기지 않습니다.

Docker가 로그인된 환경에서는 다음 명령으로 생성된 Docker 설정 파일을
확인한 뒤 그 파일의 내용을 GitLab File 변수에 넣을 수 있습니다.

```bash
docker login registry.gitlab.com
cat ~/.docker/config.json
```

Windows에서는 다음 경로를 사용합니다.

```powershell
Get-Content $env:USERPROFILE\.docker\config.json -Raw
```

## 5. 변수와 Kubernetes Secret 매핑

`sync:workload-secrets`를 실행하면 다음 Secret이 생성 또는 갱신됩니다.

| GitLab CI/CD Variable | Namespace | Kubernetes Secret |
| --- | --- | --- |
| `ATMO_API_DEV_DB_ENV` | `atmo-api-dev` | `atmo-db-secret` |
| `ATMO_API_DEV_JWT_ENV` | `atmo-api-dev` | `atmo-jwt-secret` |
| `ATMO_API_DEV_OAUTH_ENV` | `atmo-api-dev` | `atmo-oauth-secret` |
| `ATMO_API_DEV_PUBLICDATA_ENV` | `atmo-api-dev` | `atmo-publicdata-secret` |
| `ATMO_API_PROD_DB_ENV` | `atmo-api-prod` | `atmo-db-secret` |
| `ATMO_API_PROD_JWT_ENV` | `atmo-api-prod` | `atmo-jwt-secret` |
| `ATMO_API_PROD_OAUTH_ENV` | `atmo-api-prod` | `atmo-oauth-secret` |
| `ATMO_API_PROD_PUBLICDATA_ENV` | `atmo-api-prod` | `atmo-publicdata-secret` |
| `GITLAB_REGISTRY_DOCKER_CONFIG` | 모든 Atmo API/Web Namespace | `gitlab-regcred` |

현재 애플리케이션은 다음 Secret 이름을 참조합니다.

- API: `atmo-db-secret`, `atmo-jwt-secret`, `atmo-oauth-secret`,
  `atmo-publicdata-secret`
- API와 Web 이미지 Pull: `gitlab-regcred`

Cloudflare Quick Tunnel과 Redis는 현재 별도 Secret 입력이 필요하지 않습니다.
Redis 인증을 활성화하거나 Named Tunnel로 변경할 때는 별도의 Secret 관리
절차를 추가해야 합니다.

## 6. 동기화 실행

1. 위 변수를 모두 추가하거나 수정합니다.
2. GitLab의 `Build` → `Pipelines`에서 Pipeline을 실행합니다.
3. 수동 작업 `sync:workload-secrets`를 시작합니다.
4. 작업 로그에 Secret 값이 출력되지 않고 성공했는지 확인합니다.
5. 이미 실행 중인 애플리케이션이 값을 시작 시점에만 읽는다면 해당
   Deployment를 재시작합니다.

Secret 값만 변경하는 경우 Git 커밋은 필요하지 않습니다. Secret 이름과
환경별 Namespace는 `ci/sync-secrets.sh`에서 고정되어 있습니다.

## 보안 주의사항

- 실제 값을 Markdown, YAML, Issue, Merge Request, 로그에 기록하지 않습니다.
- `set -x` 또는 Secret 값을 출력하는 디버그 로그를 사용하지 않습니다.
- `.env`, Docker 인증 파일, kubeconfig를 Git에 커밋하지 않습니다.
- 토큰이 노출되면 즉시 폐기하고 새 토큰으로 교체합니다.
- GitLab 변수와 Kubernetes Secret에 접근할 수 있는 사용자 및 Runner 권한을
  최소화합니다.

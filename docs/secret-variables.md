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

로컬에서 처음 인증서를 가져올 때만 Kubernetes 접근이 필요합니다. Controller의 실제
namespace·Service 이름, Windows 셸별 명령, context 확인, PEM 검증 절차는
[`sealed-secrets-certificate.md`](sealed-secrets-certificate.md)를 따릅니다.

이후 공개 인증서의 전체 PEM 내용은 GitLab의 File Variable로 등록해 CI에서 사용할
수 있습니다. 인증서가 갱신되면 같은 절차로 다시 가져와 변수를 교체합니다.

## GitLab 변수 등록

GitLab 프로젝트에서 다음 메뉴로 이동합니다.

`Settings` → `CI/CD` → `Variables` → `Add variable`

다음 원칙으로 등록합니다.

기존 `lime985340` Group Variable에 이미 등록된 공통 값은 각 프로젝트에 다시
만들지 않습니다. Neople Game Analytics에서 사용하는 값은 아래의 두 File
Variable입니다.

- `SEALED_SECRETS_CERT`, `ATMO_API_*_ENV`, `NEOPLE_GAME_ANALYTICS_API_*_ENV`,
  `ONTOLOGY_ASAL_AGENT_*_ENV`처럼
  Job에 파일 경로로 전달되는 값은 내용이 한 줄이어도 `Type: File`로 등록
- `GITLAB_REGISTRY_USERNAME`, `GITLAB_REGISTRY_TOKEN`처럼 한 줄로 전달되는 값은
  `Type: Variable`로 등록
- `GITLAB_REGISTRY_USERNAME`, `GITLAB_REGISTRY_TOKEN`은 현재 `gitops` 프로젝트의
  CI/CD Variables에 등록되어 있습니다. 모든 서비스가 동일한 Registry credential을
  사용해야 할 때만 `lime985340` Group으로 이동하며, 프로젝트와 Group에 중복 등록하지
  않습니다.
- 이 GitOps 프로젝트의 sealing Job은 별도 Push token이 아니라 GitLab 사전 정의
  `CI_JOB_TOKEN`을 사용합니다. GitLab 프로젝트에서 Job token의 repository push를
  허용하고, 대상 Protected branch 정책도 맞아야 합니다.
- 운영 값은 `Protected`로 등록하고 실행 ref와 권한을 제한
- GitLab masking 조건을 충족하는 단일 행 Secret만 `Masked` 또는
  `Masked and hidden`으로 등록
- multiline File 변수에는 Masked 설정을 강제하지 않음
- File 변수의 Value에는 파일 경로가 아니라 파일의 실제 내용을 입력하며,
  Job 안에서는 GitLab이 만들어 준 임시 파일 경로로 제공됨
- `GITLAB_REGISTRY_TOKEN`은 `atmo`, `neople-game-analytics`,
  `ontology-asal-agent` 이미지 프로젝트를 읽을 수 있는 `read_registry` 권한만
  부여한 credential을 사용
- `SEALED_SECRETS_CERT`, `ATMO_API_*_ENV`, `NEOPLE_GAME_ANALYTICS_API_*_ENV`는
  multiline File 변수이므로 Masked를 요구하지 않음; 대신 Protected, scope, 접근
  권한과 로그 미출력으로 보호
- `GITLAB_REGISTRY_USERNAME`은 일반 Variable로 등록하고, `GITLAB_REGISTRY_TOKEN`은
  일반 Variable로 등록하되 GitLab masking 조건을 충족하면 `Masked`와 `Protected`를
  사용
- 두 값은 로그에 출력하지 않으며, CI가 Job 내부의 임시 Docker config를 생성한 뒤 정리
- `GITOPS_PUSH_TOKEN`과 `GITOPS_PUSH_TOKEN_USER`는 서비스 저장소가 별도 GitOps
  저장소로 Push하는 흐름에서만 사용하며, 이 프로젝트의 sealing Job에는 등록하지 않음
- 바이너리 파일은 CI/CD Variable에 넣지 않고 `Settings` → `CI/CD` →
  `Secure Files`에 원본 파일로 업로드합니다. 현재 목록은
  [`ci/secret-files.conf`](../ci/secret-files.conf)가 관리하며, CI가 `glab securefile`
  으로 다운로드한 뒤 선언된 매핑을 공통 sealing 함수로 처리합니다.

`CI_JOB_TOKEN`은 GitLab이 Job 실행 중 자동으로 제공하는 값이며 GitLab 변수 목록에
직접 생성하지 않습니다. Job token repository push 설정이 비활성화되어 있거나
Protected branch가 Push를 허용하지 않으면 sealing Job은 Push 단계에서 실패합니다.

`ATMO_API_*_ENV` File 변수의 내용은 `kubectl create secret --from-env-file`에
전달됩니다. 따라서 한 줄에 하나의 `KEY=VALUE`를 작성하고 `export`를 붙이지
않습니다. YAML, JSON, Markdown 코드 펜스를 값에 포함하지 않으며, File 변수
자체를 shell 스크립트나 GitLab dotenv artifact로 해석하지 않습니다. 따옴표는
shell처럼 제거되지 않으므로 `KEY="value"`가 아니라 `KEY=value`로 작성합니다.
빈 줄과 `#`로 시작하는 주석은 피하고, 값 안에 줄바꿈이 필요한 Secret은 이
env-file 형식으로 표현하지 않습니다.

## 필요한 변수

### `SEALED_SECRETS_CERT`

`kubeseal --fetch-cert`로 받은 Controller 공개 인증서 전체를 File 변수로
등록합니다. Private Key는 입력하지 않습니다.

### 바이너리 Secure Files

GraphDB 라이선스처럼 임의의 바이트를 포함할 수 있는 파일은 GitLab 프로젝트의
`Settings` → `CI/CD` → `Secure Files` → `Upload File`에서 원본 파일을 업로드합니다.
현재 등록해야 하는 이름은 다음과 같습니다.

| Secure File 이름 | Secret Namespace | Secret 이름 | Secret key |
| --- | --- | --- | --- |
| `graphdb.license` | `graphdb` | `graphdb-license` | `graphdb.license` |

Secure Files는 저장소 밖에 보관되므로 Git에 원본 또는 Base64 문자열이 들어가지
않습니다. `seal:workload-secrets`는 Job Token으로 Secure Files를 다운로드하고,
`ci/secret-files.conf`의 선언을 순회하여 `kubectl create secret --from-file`과
`kubeseal`을 실행합니다. 새 바이너리 Secret은 스크립트에 제품별 `if`를 추가하지
않고 manifest에 한 줄만 추가합니다. Secure File 내용은 Job 로그에 출력하지
않습니다. Secure File 업로드를 확인한 뒤 기존 `GRAPHDB_LICENSE_FILE` CI/CD
변수는 삭제합니다. 새 파이프라인은 해당 변수를 읽지 않습니다.

### GitOps sealing Job의 Push 인증

이 프로젝트의 `seal:workload-secrets`는 별도 `GITOPS_PUSH_TOKEN`이나
`GITOPS_PUSH_TOKEN_USER`를 사용하지 않습니다. GitLab이 Job 실행 중 제공하는
`CI_JOB_TOKEN`과 고정 username `gitlab-ci-token`으로 현재 GitOps 저장소에 Push합니다.

GitLab 프로젝트에서 Job token의 repository push 허용 설정을 켜야 하며, Protected
branch 정책은 그대로 적용됩니다. 이 설정을 켜도 Job token이 Protected branch
제한을 우회하지는 않습니다. 저장소 외부의 `atmo-api`/`atmo-web` 서비스 CI가 이
저장소로 Push하는 별도 흐름은 여전히 `docs/image-updates.md`의
`GITOPS_PUSH_TOKEN`, `GITOPS_PUSH_TOKEN_USER`, `GITOPS_BRANCH` 계약을 사용합니다.

Protected 변수는 Protected ref에서만 Job에 전달됩니다. 현재 sealing 대상인
`main` 브랜치는 Protected로 관리합니다. `feature/clean-gitops-layout`은 검토용
Protected 브랜치로 유지합니다.

### API DB/Redis

변수명:

- `ATMO_API_DEV_DB_ENV`
- `ATMO_API_PROD_DB_ENV`

```env
SPRING_DATASOURCE_URL=jdbc:postgresql://<DB_HOST>:5432/<DB_NAME>
SPRING_DATASOURCE_USERNAME=<DB_USERNAME>
SPRING_DATASOURCE_PASSWORD=<DB_PASSWORD>
SPRING_REDIS_HOST=redis-master.redis.svc.cluster.local
SPRING_REDIS_PORT=6379
```

개발과 운영은 각각 별도 DB 값을 사용합니다.

### JWT

변수명:

- `ATMO_API_DEV_JWT_ENV`
- `ATMO_API_PROD_JWT_ENV`

```env
JWT_ACCESS_SECRET=<LONG_RANDOM_ACCESS_SECRET>
JWT_REFRESH_SECRET=<LONG_RANDOM_REFRESH_SECRET>
JWT_ACCESS_TTL_SECONDS=900
JWT_REFRESH_TTL_SECONDS=2592000
```

Access와 Refresh Secret은 서로 다른 충분히 긴 랜덤 값을 사용합니다. 키 이름은
`JWT_ACCESS_SECRET`/`JWT_REFRESH_SECRET`이며, `APP_JWT_*`로 작성하지 않습니다.
현재 Kustomize projected Secret이 이 키를 `/etc/secrets/app/jwt/...`로 전달합니다.

### OAuth

변수명:

- `ATMO_API_DEV_OAUTH_ENV`
- `ATMO_API_PROD_OAUTH_ENV`

```env
KAKAO_CLIENT_ID=<KAKAO_CLIENT_ID>
KAKAO_CLIENT_SECRET=<KAKAO_CLIENT_SECRET>
KAKAO_REDIRECT_URI=https://<PUBLIC_HOST>/atmo/api/v1/auth/oauth/kakao/callback

GOOGLE_CLIENT_ID=<GOOGLE_CLIENT_ID>
GOOGLE_CLIENT_SECRET=<GOOGLE_CLIENT_SECRET>
GOOGLE_REDIRECT_URI=https://<PUBLIC_HOST>/atmo/api/v1/auth/oauth/google/callback

NAVER_CLIENT_ID=<NAVER_CLIENT_ID>
NAVER_CLIENT_SECRET=<NAVER_CLIENT_SECRET>
NAVER_REDIRECT_URI=https://<PUBLIC_HOST>/atmo/api/v1/auth/oauth/naver/callback
```

이 블록은 현재 GitOps workload가 실제로 마운트하는 Secret 키 이름과 일치합니다.
OAuth 인증에 필요한 Client ID/Secret과 provider 콘솔에 등록한 Redirect URI만
GitLab File 변수에 넣습니다. OAuth authorize/token/userinfo endpoint와 scope는
현재 GitOps Secret에서 사용하지 않으므로 입력하지 않습니다.

Redirect URI는 실제 공개 호스트와 provider 콘솔에 등록한 값으로 바꿉니다.
현재 외부 경로는 `/atmo/api/v1/auth/oauth/.../callback`이며, Traefik이
`/atmo`를 제거한 뒤 API 내부의 `/api/v1` Controller로 전달합니다.

### 공공데이터 API

변수명:

- `ATMO_API_DEV_PUBLICDATA_ENV`
- `ATMO_API_PROD_PUBLICDATA_ENV`

```env
PUBLIC_SERVICE_KEY=<PUBLIC_DATA_SERVICE_KEY>
```

이 키 이름은 API Deployment와 ingestion CronJob이 projected Secret에서 읽는 이름과
같습니다. 내용이 한 줄이어도 CI가 `--from-env-file`에 파일 경로를 전달하므로 이
변수는 `File` 타입으로 등록합니다.

### atmo-web 빌드 변수

atmo-web의 다음 값은 GitOps `ATMO_API_*_ENV` File 변수에 넣지 않습니다. 서비스
저장소의 CI/CD Variables에서 각각 일반 `Variable`로 설정하고 Docker build argument로
전달합니다.

```text
VITE_API_BASE_URL=/atmo/api/v1
VITE_KAKAO_APP_KEY=<PUBLIC_KAKAO_APP_KEY>
```

`VITE_KAKAO_APP_KEY`는 프런트엔드 번들에 포함되는 공개 값입니다. OAuth client
secret은 이 변수나 frontend에 넣지 말고 API의 `ATMO_API_DEV_OAUTH_ENV` 또는
`ATMO_API_PROD_OAUTH_ENV` File 변수에만 입력합니다.

`VITE_API_BASE_URL`은 Kubernetes Secret이 아니라 atmo-web 이미지 빌드 시
주입되는 GitLab CI/CD Variable입니다. `/atmo` 경로 전환 후 반드시
`/atmo/api/v1`로 변경하고 새 Web 이미지를 빌드해야 합니다.

### Refresh Cookie 경로

Refresh Token Cookie는 API 코드의 `APP_AUTH_REFRESH_COOKIE_PATH` 설정을 사용합니다.
운영 GitOps Deployment는 다음 공개 경로를 설정합니다.

```text
APP_AUTH_REFRESH_COOKIE_PATH=/atmo/api/v1/auth/refresh
```

이 값은 인증 비밀값이 아니므로 OAuth Secret File 변수에 넣지 않습니다. 기존
`/api/v1/auth/refresh` Cookie가 브라우저에 남아 있다면 `/atmo` 전환 후 새 로그인
또는 로그아웃으로 정리합니다.

### GitLab Container Registry

서비스 이미지가 `registry.gitlab.com/lime985340/atmo-api`와
`registry.gitlab.com/lime985340/atmo-web`,
`registry.gitlab.com/lime985340/neople-game-analytics-api`,
`registry.gitlab.com/lime985340/neople-game-analytics-web`에서 Pull됩니다.
따라서 하나의 Registry credential이 네 프로젝트의 이미지를 모두 읽을 수 있어야
합니다. GitOps 프로젝트 하나에만 만든 Deploy Token은 다른 프로젝트 이미지 Pull
권한이 부족할 수 있습니다.

이 값은 프로젝트별 변수가 아니라 `lime985340` Group 변수로 등록합니다.

| Group Variable | Type | 용도 |
| --- | --- | --- |
| `GITLAB_REGISTRY_USERNAME` | Variable | Registry credential username |
| `GITLAB_REGISTRY_TOKEN` | Variable | 네 이미지 프로젝트를 읽는 `read_registry` token |

Group 변수의 `Environment scope`는 기본값 `*`로 두고, 운영 정책에 맞게
`Protected`를 사용합니다. 하위 프로젝트에 같은 이름의 변수를 추가하면 GitLab
변수 우선순위에 따라 Group 값이 가려질 수 있으므로 중복 등록하지 않습니다.

Group 변수명:

- `GITLAB_REGISTRY_USERNAME` - 일반 `Variable`
- `GITLAB_REGISTRY_TOKEN` - 일반 `Variable`

두 값 모두 `lime985340` Group의 CI/CD Variables에 한 줄로 입력합니다.
`GITLAB_REGISTRY_TOKEN`에는 네 이미지 프로젝트에 대한 `read_registry` 권한만
부여합니다. 사용자가 Docker
`config.json`을 만들거나 `auth`를 Base64로 계산할 필요는 없습니다. CI가 Job 내부의
보호된 임시 디렉터리에 다음 구조를 생성한 뒤 SealedSecret으로 암호화합니다.

```json
{
  "auths": {
    "registry.gitlab.com": {
      "username": "<GITLAB_REGISTRY_USERNAME>",
      "password": "<GITLAB_REGISTRY_TOKEN>",
      "auth": "<CI가 username:token 전체를 Base64로 생성>"
    }
  }
}
```

이 JSON은 예시 구조일 뿐이며 GitLab 변수에 직접 입력하지 않습니다. Registry
username/token은 로그, 채팅, Git, artifact에 출력하지 않습니다. 기존
`GITLAB_REGISTRY_DOCKER_CONFIG` File 변수는 사용하지 않습니다.

### Neople Worker

일일 Worker CronJob만 Neople API Key를 사용합니다. API Deployment와 Web
Deployment에는 이 Secret을 주입하지 않습니다. 따라서 Dev와 Prod에 각각
별도의 File 변수를 등록합니다.

- `NEOPLE_GAME_ANALYTICS_API_DEV_ENV` → `neople-game-analytics-api-dev`
- `NEOPLE_GAME_ANALYTICS_API_PROD_ENV` → `neople-game-analytics-api-prod`

두 File 변수의 기본 형식은 다음과 같습니다.

```env
DNF_API_KEY=<DNF_API_KEY>
CYPHERS_API_KEY=<CYPHERS_API_KEY>
```

`DEV`와 `PROD`는 각각 게임별로 발급한 DNF API Key와 Cyphers API Key를
입력합니다. 두 게임의 키를 하나의 값으로 합치거나 공통 `NEOPLE_API_KEY`로
대체하지 않습니다.

다음 값은 Secret File 변수에 넣지 않습니다.

- `DNF_SERVERS`, `DNF_FAME_BANDS`, `DNF_SAMPLE_LIMIT`, `DNF_AUCTION_ITEM_LIMIT`:
  API ConfigMap의 수집 설정
- `CYPHERS_*`, `PUBLIC_DASHBOARD_PATH`, `CORS_ALLOW_ORIGINS`: 비밀이 아닌
  애플리케이션 설정

Worker는 `envFrom`으로 Secret과 ConfigMap을 함께 읽습니다. API Deployment는
ConfigMap만 읽습니다. Worker가 생성한
`data/public/dashboard.json`은 API와 공유하는 PersistentVolume에 저장되며, API가
`/api/dashboard`로 제공합니다. Web은 API 경로를 프록시하므로 Worker 실행 후 Web
이미지를 다시 빌드하지 않아도 최신 공개 JSON을 표시합니다.

`neople-game-analytics-data`는 현재 `ReadWriteOnce` 1Gi PVC입니다. API와 Worker가
같은 노드에서 이 볼륨을 사용하도록 동작하며, 여러 노드에서 자유롭게 공유해야
하는 클러스터라면 사용하는 StorageClass가 `ReadWriteMany`를 지원하는지 확인한
뒤 access mode를 별도로 조정해야 합니다.

### Ontology ASAL Agent

Dev와 Prod는 서로 다른 Namespace와 SealedSecret을 사용하므로 Agent 런타임
변수도 환경별로 분리합니다.

- `ONTOLOGY_ASAL_AGENT_DEV_ENV` → `ontology-asal-agent-api-dev`
- `ONTOLOGY_ASAL_AGENT_PROD_ENV` → `ontology-asal-agent-api-prod`

두 File 변수의 형식은 다음과 같습니다.

```env
TRIPLESTORE_USERNAME=<reader username, when GraphDB security is enabled>
TRIPLESTORE_PASSWORD=<reader password, when GraphDB security is enabled>
```

CLIProxyAPI 접근은 Cilium 정책으로 제한하므로 `LLM_API_KEY`는 입력하지
않습니다. `LLM_PROVIDER=codex_proxy`인 API는 빈 키로 내부 Proxy를 호출합니다.

GraphDB 라이선스는 Agent 환경별로 복제하지 않고 공용 플랫폼 Secret으로 관리합니다.

- Secure File `graphdb.license` → `graphdb` / `graphdb-license`

`graphdb.license` Secure File은 온톨로지 RDF 쓰기에 필요한 값이므로 누락되면
`seal:workload-secrets`가 실패하며 빈 GraphDB license Secret을 생성하지 않습니다.
Secure File의 원본 바이트는 CI에서 Base64로 변환하거나 GraphDB 전용 예외로
처리하지 않습니다. `Protected` 변수인 `SEALED_SECRETS_CERT`의 경우에는 실행
대상 브랜치도 Protected ref여야 합니다.

#### 운영 보안 기준

현재 `main`의 GraphDB는 테스트 부트스트랩을 위해
`security.enabled: false`, `service.type: ClusterIP`, `ingress.enabled: false`로
구성되어 있습니다. 이 상태에서는 GraphDB username/password가 필요하지 않지만,
운영 환경에서는 GraphDB 보안을 활성화하고 전용 계정을 사용해야 합니다.

- GraphDB bootstrap/admin 계정은 초기 사용자 관리에만 사용하고 애플리케이션에
  전달하지 않습니다.
- API에는 `asal-agent` repository에 query/read 권한만 있는 환경별 reader 계정을
  사용합니다.
- 온톨로지 적재 Migration Job에는 reader와 분리된 writer 계정을 사용합니다.
- Google/GitLab 로그인 비밀번호와 GitLab PAT를 GraphDB 비밀번호로 재사용하지
  않습니다.
- GraphDB license가 필요한 RDF transaction과 온톨로지 적재에는 실제
  `graphdb.license` Secure File을 등록합니다. placeholder는 운영값으로 간주하지
  않습니다.

운영 API File 변수에는 환경별 GraphDB 인증값 등 실제 Secret 값만 입력합니다.
현재 Feature 클러스터의 CLIProxyAPI 접근은 Cilium 정책으로 제한하므로 Proxy
접근용 키를 별도로 입력하지 않습니다.

```env
TRIPLESTORE_USERNAME=<환경별 GraphDB reader 계정>
TRIPLESTORE_PASSWORD=<환경별 GraphDB reader 비밀번호>
```

현재 Agent의 클러스터 LLM 설정은 CLIProxyAPI입니다.

```env
LLM_PROVIDER=codex_proxy
LLM_BASE_URL=http://cli-proxy-api.<proxy-namespace>.svc.cluster.local:8317/v1
LLM_MODEL=<proxy model alias>
```

위 값들은 GitOps 환경별 ConfigMap이 관리하므로 File 변수에 반복해서 넣지
않습니다. ChatGPT Plus/Codex OAuth 원본 토큰은 GitLab CI나 이 File 변수에
넣지 않고 Proxy의 환경별 PVC에 저장합니다. OpenRouter 값은 Proxy 없이 API를
로컬 단독 실행할 때만 사용하는 fallback입니다.

현재 `ontology-asal-agent` Migration Job은 ConfigMap만 읽도록 되어 있으므로,
GraphDB 보안을 활성화하기 전에 환경별 writer Secret을 Job에 연결해야 합니다.
reader 비밀번호를 writer 용도로 재사용하거나 관리자 계정을 Job에 넣지 않습니다.

GraphDB 보안 활성화, bootstrap Secret, reader/writer 분리, 클러스터 검증 절차의
전체 내용은 [`ontology-asal-agent-security.md`](ontology-asal-agent-security.md)를
참조합니다.

### CLIProxyAPI

CLIProxyAPI는 온톨로지에 종속되지 않는 공용 Proxy입니다. 온톨로지 API 외에도
OpenAI-compatible API를 사용할 다른 서비스가 같은 환경의 Proxy Service를
호출할 수 있습니다.

별도의 CLIProxyAPI Secret 변수는 사용하지 않습니다. Proxy는 외부에 공개하지
않고 `platform/policies`의 Cilium 정책에서 온톨로지 API Pod만 환경별
`8317/TCP`로 접근하도록 제한합니다. Proxy의 Codex OAuth 인증정보는
`cli-proxy-api-auth` PVC에 저장하며 GitLab CI나 Git에 넣지 않습니다.

CLIProxyAPI의 Codex OAuth 로그인은 Secret sealing Pipeline이 대신 수행하지
않습니다. Argo CD가 Proxy Deployment와 `cli-proxy-api-auth` PVC를 생성한 뒤
환경별로 한 번만 `kubectl exec deploy/cli-proxy-api`를 실행합니다. 로그인 결과는
PVC에 저장되므로 Pod 재생성마다 다시 로그인하지 않습니다.

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
| `gitops` 프로젝트의 `GITLAB_REGISTRY_USERNAME` + `GITLAB_REGISTRY_TOKEN` | Atmo API/Web 각 Namespace | `gitlab-regcred` |
| `NEOPLE_GAME_ANALYTICS_API_DEV_ENV` | `neople-game-analytics-api-dev` | `neople-game-analytics-api-secret` |
| `NEOPLE_GAME_ANALYTICS_API_PROD_ENV` | `neople-game-analytics-api-prod` | `neople-game-analytics-api-secret` |
| `gitops` 프로젝트의 `GITLAB_REGISTRY_USERNAME` + `GITLAB_REGISTRY_TOKEN` | Neople API/Web 각 Namespace | `gitlab-regcred` |
| `ONTOLOGY_ASAL_AGENT_DEV_ENV` | `ontology-asal-agent-api-dev` | `ontology-asal-agent-secrets` |
| `ONTOLOGY_ASAL_AGENT_PROD_ENV` | `ontology-asal-agent-api-prod` | `ontology-asal-agent-secrets` |
| `lime985340` Group의 `GITLAB_REGISTRY_USERNAME` + `GITLAB_REGISTRY_TOKEN` | `ontology-asal-agent-api-dev` / `ontology-asal-agent-web-dev` | `gitlab-regcred` |
| `lime985340` Group의 `GITLAB_REGISTRY_USERNAME` + `GITLAB_REGISTRY_TOKEN` | `ontology-asal-agent-api-prod` / `ontology-asal-agent-web-prod` | `gitlab-regcred` |
| Secure File `graphdb.license` | `graphdb` | `graphdb-license` |

생성되는 파일은 다음과 같습니다.

```text
workloads/atmo/api/environments/dev/sealed-secrets.yaml
workloads/atmo/api/environments/prod/sealed-secrets.yaml
workloads/atmo/web/environments/dev/sealed-secrets.yaml
workloads/atmo/web/environments/prod/sealed-secrets.yaml
workloads/neople-game-analytics/api/environments/dev/sealed-secrets.yaml
workloads/neople-game-analytics/api/environments/prod/sealed-secrets.yaml
workloads/neople-game-analytics/web/environments/dev/sealed-secrets.yaml
workloads/neople-game-analytics/web/environments/prod/sealed-secrets.yaml
workloads/ontology-asal-agent/api/environments/dev/sealed-secrets.yaml
workloads/ontology-asal-agent/api/environments/prod/sealed-secrets.yaml
workloads/ontology-asal-agent/web/environments/dev/sealed-secrets.yaml
workloads/ontology-asal-agent/web/environments/prod/sealed-secrets.yaml
platform/graphdb/sealed-secret.yaml
```

파일 안에는 `encryptedData`만 저장되며 실제 값은 저장되지 않습니다.
SealedSecret의 이름과 Namespace는 암호화 시점과 적용 시점에 같아야 합니다.

`NEOPLE_GAME_ANALYTICS_API_*_ENV` File 변수의 전체 예시는 위의
`Neople Worker` 절을 따릅니다. Secret이 아직 생성되지 않아도 API 컨테이너는
기동하지만, 필수 환경변수가 없으면 Worker 수집 작업이 실패할 수 있습니다.
대시보드 API는 `/neople/api/dashboard`로 노출되며, Power BI Embed 설정은
사용하지 않습니다.

## 동기화 실행

1. 위 GitLab 변수를 등록하거나 수정합니다.
2. `Build` → `Pipelines` → `New pipeline`에서
   현재 작업 중인 Feature 브랜치(현재는 `feature/clean-gitops-layout`)를 선택합니다.
3. `Inputs`의 boolean `update_secrets`를 `true`로 설정하고 Pipeline을 실행합니다.
4. 수동 작업 `seal:workload-secrets`를 실행합니다.
5. CI가 `kubeseal`로 YAML을 생성하고 같은 Feature 브랜치에 Push합니다.
6. GitOps validation Job이 변경사항을 검증합니다.
7. Feature 브랜치의 Merge Request를 검토합니다.
8. 현재 검증 클러스터에서는 Argo CD가
   `feature/clean-gitops-layout`의 변경된 SealedSecret을 동기화합니다.
   운영 전환 시 검토가 끝난 변경사항을 `main`에 병합하고 운영 Argo CD를
   `main`에 연결합니다.
9. Controller가 일반 Kubernetes Secret을 생성하면 각 서비스가 새 값을 사용합니다.

GraphDB license 반영 성공 여부는 Job 로그의
`Generated encrypted SealedSecret graphdb/graphdb-license` 메시지와
`platform/graphdb/sealed-secret.yaml`의 비어 있지 않은 `encryptedData`로
확인합니다. 암호문 외에 license 원문은 Git이나 로그에 남기지 않습니다.

Secret 값은 GitLab CI/CD Variables에만 저장하며 Pipeline 입력 화면에는 입력하지
않습니다. 일반 `UPDATE_SECRETS` Pipeline 변수는 사용하지 않습니다.

### Codex 최초 로그인

Proxy Deployment와 PVC가 Argo CD로 생성되고 Secret이 동기화된 뒤, 환경별로 한
번만 다음 명령을 실행합니다. 두 명령을 모두 실행하지 말고 첫 번째가 성공하면
종료합니다.

```bash
kubectl -n cli-proxy-api-dev exec -it deploy/cli-proxy-api -- \
  ./CLIProxyAPI --config /etc/cli-proxy-api/config.yaml -codex-device-login
```

Device Login을 사용할 수 없는 경우에만 일반 OAuth 방식을 사용합니다.

```bash
kubectl -n cli-proxy-api-dev exec -it deploy/cli-proxy-api -- \
  ./CLIProxyAPI --config /etc/cli-proxy-api/config.yaml -codex-login -no-browser
```

첫 번째 방식이 성공하면 Codex OAuth 인증정보는
`/root/.cli-proxy-api`에 마운트된 `cli-proxy-api-auth` PVC에 저장됩니다. 이후
Pod가 교체되어도 같은 PVC를 재사용하므로 다시 로그인하지 않습니다. PVC 삭제,
OAuth 세션 폐기, refresh 인증 만료 때만 재로그인이 필요합니다.

## Pipeline trigger

Normal pushes run the manifest validation jobs only. The Secret sealing job is
created only for a manually started web pipeline whose typed input is enabled.

The `update_secrets` boolean input is declared by the root `spec:inputs` section
in `.gitlab-ci.yml`. Its default is `false`, and push pipelines cannot create the
sealing job. If the Inputs section is empty, ensure the updated feature-branch CI
configuration has been loaded; do not loosen the project setting that disallows
ad-hoc pipeline variables.

A push authenticated with `CI_JOB_TOKEN` does not start another pipeline, and the
sealing job's manual web-pipeline rule prevents a recursive sealing run. The
GitOps sealing job uses `CI_JOB_TOKEN`; the service repositories' separate
image-update jobs use `GITOPS_PUSH_TOKEN`, `GITOPS_PUSH_TOKEN_USER`, and
`GITOPS_BRANCH`, inherited from the `lime985340` Group.

### GitLab project metadata

Keep the sealing variables in the GitOps project with the documented types and
protect them according to the branch policy. The GitOps project does not need a
`GITOPS_PUSH_TOKEN` or the legacy `GITLAB_REGISTRY_DOCKER_CONFIG` variable.
Protected variables are provided only to Protected refs, so the selected feature
branch must remain Protected when the sealing job needs those values.

The GitLab project setting that disallows ordinary pipeline-variable overrides is
intentional and remains unchanged; typed CI inputs are the supported operator
control for this manual job.

Secret 값을 변경할 때마다 Git 커밋이 생성됩니다. 애플리케이션이 값을 시작
시점에만 읽는다면 Secret 동기화 후 해당 Deployment를 재시작해야 합니다.

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

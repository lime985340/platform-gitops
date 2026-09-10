# CLIProxyAPI 공용 운영 구성

## 역할

`cli-proxy-api`는 온톨로지 전용이 아닌 공용 LLM Proxy입니다. 온톨로지 API와
다른 내부 서비스가 OpenAI-compatible API로 사용할 수 있습니다.

별도 CLIProxyAPI 소스 저장소는 현재 필요하지 않습니다. GitOps가 공식 이미지의
고정 버전, Deployment, Service, PVC, Secret 참조를 관리합니다.

```text
workloads/platform/cli-proxy-api/resources/
workloads/platform/cli-proxy-api/environments/dev/
workloads/platform/cli-proxy-api/environments/prod/
```

환경별 Service DNS는 다음과 같습니다.

```text
http://cli-proxy-api.platform-cli-proxy-api-dev.svc.cluster.local:8317/v1
http://cli-proxy-api.platform-cli-proxy-api-prod.svc.cluster.local:8317/v1
```

Proxy는 `ClusterIP`로만 노출합니다. 관리 API와 OAuth callback 포트는 Ingress나
일반 Service로 공개하지 않습니다.

## Secret Pipeline

GitLab File Variable을 등록합니다.

```text
CLI_PROXY_API_DEV_ENV
CLI_PROXY_API_PROD_ENV
```

각 변수의 파일 내용은 다음 한 줄입니다.

```env
PROXY_API_KEY=<long-random-proxy-client-key>
```

`seal:workload-secrets` Job이 이 값을 `kubeseal`로 암호화하여 다음 파일에
SealedSecret을 생성합니다.

```text
workloads/platform/cli-proxy-api/environments/dev/sealed-secrets.yaml
workloads/platform/cli-proxy-api/environments/prod/sealed-secrets.yaml
```

생성되는 Secret은 다음 이름을 사용합니다.

```text
platform-cli-proxy-api-dev/cli-proxy-api-secrets
platform-cli-proxy-api-prod/cli-proxy-api-secrets
```

온톨로지 API의 `ONTOLOGY_ASAL_AGENT_DEV_ENV` 또는
`ONTOLOGY_ASAL_AGENT_PROD_ENV`에는 같은 키를 다음처럼 입력합니다.

```env
LLM_API_KEY=<same-value-as-PROXY_API_KEY>
```

`PROXY_API_KEY`는 Proxy 접근용 키이며 Codex OAuth 원본 토큰이 아닙니다.

## Codex OAuth 최초 로그인

Secret Pipeline은 Codex 계정 로그인을 수행하지 않습니다. Argo CD가 Deployment와
PVC를 생성하고 Secret을 동기화한 뒤, 환경별로 한 번만 로그인합니다.

Device Login을 먼저 시도합니다.

```bash
kubectl -n platform-cli-proxy-api-dev exec -it deploy/cli-proxy-api -- \
  ./CLIProxyAPI --config /etc/cli-proxy-api/config.yaml -codex-device-login
```

Device Login이 지원되지 않거나 실패한 경우에만 일반 OAuth 로그인으로 진행합니다.

```bash
kubectl -n platform-cli-proxy-api-dev exec -it deploy/cli-proxy-api -- \
  ./CLIProxyAPI --config /etc/cli-proxy-api/config.yaml -codex-login -no-browser
```

두 명령을 모두 실행하는 것이 아니라 하나만 성공시키면 됩니다. 로그인 결과는
`/root/.cli-proxy-api`에 마운트된 `cli-proxy-api-auth` PVC에 저장됩니다.

이후 Pod가 재생성되어도 같은 PVC를 다시 마운트하므로 재로그인하지 않습니다.
PVC 삭제, OAuth 세션 폐기, refresh 인증 만료 때만 다시 로그인합니다.

Prod도 동일한 절차를 `platform-cli-proxy-api-prod` Namespace에서 수행하되,
Dev와 Prod는 서로 다른 Proxy 키와 PVC를 사용합니다.

## 클라이언트 설정

온톨로지 API 또는 다른 서비스는 다음 형태로 연결합니다.

```env
LLM_PROVIDER=codex_proxy
LLM_BASE_URL=http://cli-proxy-api.platform-cli-proxy-api-dev.svc.cluster.local:8317/v1
LLM_API_KEY=<PROXY_API_KEY>
LLM_MODEL=<cli-proxy-api의 /v1/models에 표시된 모델명>
```

모델명은 Proxy 인증 후 `/v1/models` 응답에서 확인합니다. Proxy 자체의 Codex
OAuth 인증과 클라이언트의 `LLM_API_KEY` 인증은 서로 다른 단계입니다.

## 운영 원칙

- Proxy는 환경별 1개 Pod와 `ReadWriteOnce` PVC로 시작합니다.
- OAuth 인증 디렉터리는 `emptyDir`에 저장하지 않습니다.
- `config.yaml`, OAuth 파일, Proxy 키를 Git에 평문으로 저장하지 않습니다.
- 이미지 버전은 `latest`가 아닌 고정 버전을 사용합니다.
- 이미지 변경은 Argo Image Updater가 아니라 GitOps Merge Request로 진행합니다.

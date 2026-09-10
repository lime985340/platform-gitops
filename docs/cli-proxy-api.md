# CLIProxyAPI 공용 운영 구성

## 역할

`cli-proxy-api`는 온톨로지 전용이 아닌 공용 LLM Proxy입니다. 온톨로지 API와
다른 내부 서비스가 OpenAI-compatible API로 사용할 수 있습니다.

별도 CLIProxyAPI 소스 저장소는 현재 필요하지 않습니다. GitOps가 공식 이미지의
고정 버전, Deployment, Service, PVC, ConfigMap을 관리합니다.

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

## Cilium 접근 제어

CLIProxyAPI는 외부 Ingress 없이 `ClusterIP`로만 노출합니다. 애플리케이션
API 키를 별도로 발급하지 않고, GitOps의 Cilium 정책이 접근 가능한 Pod와
포트를 제한합니다.

- `ontology-asal-agent-api-dev`의 API Pod → Dev Proxy `8317/TCP`만 허용
- `ontology-asal-agent-api-prod`의 API Pod → Prod Proxy `8317/TCP`만 허용
- 그 외 Pod → CLIProxyAPI 차단
- CLIProxyAPI → Codex 인증 및 upstream의 `443/TCP`만 허용

따라서 `CLI_PROXY_API_DEV_ENV`, `CLI_PROXY_API_PROD_ENV`,
`PROXY_API_KEY`, `LLM_API_KEY`는 클러스터 Proxy 연결에 사용하지 않습니다.
API가 `codex_proxy`를 사용할 때 빈 `LLM_API_KEY`로 동작하며, 요청에도
`Authorization` 헤더를 추가하지 않습니다. 새로운 내부 소비자를 추가할 때는
임의의 키를 공유하는 대신 Cilium 정책에 해당 Pod 라벨과 Namespace를 명시합니다.

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

Prod도 동일한 절차를 `platform-cli-proxy-api-prod` Namespace에서 수행합니다.
Dev와 Prod는 서로 다른 OAuth PVC를 사용하므로 인증 세션은 환경별로 분리됩니다.

## 클라이언트 설정

온톨로지 API 또는 다른 서비스는 다음 형태로 연결합니다.

```env
LLM_PROVIDER=codex_proxy
LLM_BASE_URL=http://cli-proxy-api.platform-cli-proxy-api-dev.svc.cluster.local:8317/v1
LLM_MODEL=<cli-proxy-api의 /v1/models에 표시된 모델명>
```

모델명은 Proxy의 `/v1/models` 응답에서 확인합니다. Proxy 자체의 Codex OAuth
인증은 클라이언트 API 키와 별개이며, OAuth 정보는 Proxy PVC에만 저장합니다.

## 운영 원칙

- Proxy는 환경별 1개 Pod와 `ReadWriteOnce` PVC로 시작합니다.
- OAuth 인증 디렉터리는 `emptyDir`에 저장하지 않습니다.
- `config.yaml`에는 Proxy 키를 넣지 않으며, OAuth 파일을 Git에 저장하지 않습니다.
- 이미지 버전은 `latest`가 아닌 고정 버전을 사용합니다.
- 이미지 변경은 Argo Image Updater가 아니라 GitOps Merge Request로 진행합니다.
- Cilium 정책을 우회하기 위해 Proxy Service를 외부에 공개하지 않습니다.

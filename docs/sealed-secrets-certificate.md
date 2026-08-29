# Sealed Secrets 인증서 등록

이 문서는 현재 배포 클러스터의 Sealed Secrets Controller **공개 인증서**를 가져와 GitLab의 `SEALED_SECRETS_CERT` File 변수로 등록하는 절차입니다.

인증서 등록만으로는 애플리케이션 Secret이 생성되지 않으며, 파이프라인도 자동으로 실행되지 않습니다. 실제 애플리케이션 Secret 값과 `seal:workload-secrets` 실행은 별도 절차입니다.

## 이 문서에서 다루는 값

`SEALED_SECRETS_CERT`에는 다음 값을 넣습니다.

- 대상 Kubernetes 클러스터의 Sealed Secrets Controller 공개 인증서
- `kubeseal --fetch-cert`로 가져온 PEM 인증서
- CI가 `kubeseal --cert`로 읽을 공개 정보

다음 값은 넣지 않습니다.

- Controller Private Key
- `kubeconfig`
- Windows 인증서 저장소의 인증서
- Kubernetes Secret YAML
- GitLab Access Token
- 인증서 파일의 로컬 경로

Controller Private Key는 기존 SealedSecret 복호화에 필요한 민감한 키입니다. 이 등록 절차에서 GitLab 변수·CI·Git에 사용하지 마세요. Private Key 백업과 복구는 [`sealed-secrets-recovery.md`](sealed-secrets-recovery.md)의 별도 절차를 따릅니다.

## 저장소의 Controller 설정

`argocd/applications/sealed-secrets.yaml` 기준 설정은 다음과 같습니다.

```text
namespace: sealed-secrets
fullnameOverride: sealed-secrets-controller
```

따라서 예상되는 Deployment와 Service 이름은 `sealed-secrets-controller`입니다. 단, 실제 클러스터의 Service 조회 결과를 항상 우선합니다. `kubeseal --controller-name`에는 Deployment 이름이 아니라 **Service 이름**을 지정합니다.

## 1. 대상 클러스터와 context 고정

인증서를 가져오는 셸과 같은 셸에서 대상 클러스터를 확인합니다. `kubectl cluster-info`는 연결 가능성만 확인하므로, API 서버 주소와 클라우드 계정·프로젝트·클러스터 식별자도 운영 기록과 대조합니다.

### Windows PowerShell

아래 예시의 경로와 context 이름을 실제 값으로 바꿉니다. `<...>` 표기는 그대로 입력하지 않습니다.

```powershell
$KubeConfigFile = "C:\path\to\known-kubeconfig"
$KubeContext = "정확한-context-이름"

kubectl --kubeconfig $KubeConfigFile --context $KubeContext config current-context
kubectl --kubeconfig $KubeConfigFile --context $KubeContext cluster-info
kubectl --kubeconfig $KubeConfigFile --context $KubeContext config get-contexts
```

### Git Bash 또는 WSL

```bash
KUBECONFIG_FILE="/c/path/to/known-kubeconfig"
KUBE_CONTEXT="정확한-context-이름"

kubectl --kubeconfig "$KUBECONFIG_FILE" --context "$KUBE_CONTEXT" config current-context
kubectl --kubeconfig "$KUBECONFIG_FILE" --context "$KUBE_CONTEXT" cluster-info
kubectl --kubeconfig "$KUBECONFIG_FILE" --context "$KUBE_CONTEXT" config get-contexts
```

PowerShell과 Git Bash/WSL은 서로 다른 `KUBECONFIG`를 사용할 수 있습니다. 검증과 인증서 취득을 서로 다른 셸에서 나누지 말고, 이후 모든 Kubernetes API 명령과 `kubeseal --fetch-cert`에 같은 kubeconfig와 context를 사용합니다.

## 2. Controller 상태와 Service 확인

### PowerShell

```powershell
kubectl --kubeconfig $KubeConfigFile --context $KubeContext -n sealed-secrets get deployment sealed-secrets-controller
kubectl --kubeconfig $KubeConfigFile --context $KubeContext -n sealed-secrets rollout status deployment/sealed-secrets-controller --timeout=120s
kubectl --kubeconfig $KubeConfigFile --context $KubeContext -n sealed-secrets get service sealed-secrets-controller -o wide
kubectl --kubeconfig $KubeConfigFile --context $KubeContext -n sealed-secrets get service sealed-secrets-controller -o jsonpath='{.spec.ports[0].name}{" / "}{.spec.ports[0].port}{"\n"}'
kubectl --kubeconfig $KubeConfigFile --context $KubeContext -n sealed-secrets get endpointslice -l kubernetes.io/service-name=sealed-secrets-controller
kubectl --kubeconfig $KubeConfigFile --context $KubeContext -n sealed-secrets get pods
```

`sealed-secrets-controller` Service가 실제로 존재하고 적어도 하나의 포트를 가지는지
확인합니다. `kubeseal`은 이 Service를 Kubernetes Service proxy로 조회하므로,
Service의 selector가 Ready Controller Pod를 가리키는지도 확인합니다. EndpointSlice는
readiness를 진단하는 보조 자료입니다. 클러스터가 EndpointSlice만 제공하거나 legacy
`Endpoints`가 비어 있어도 Service와 Controller가 정상이라면 legacy Endpoints만을
근거로 중단하지 않습니다.

```powershell
kubectl --kubeconfig $KubeConfigFile --context $KubeContext -n sealed-secrets get service sealed-secrets-controller
kubectl --kubeconfig $KubeConfigFile --context $KubeContext -n sealed-secrets get service sealed-secrets-controller -o jsonpath='{.spec.selector}{"\n"}'
kubectl --kubeconfig $KubeConfigFile --context $KubeContext -n sealed-secrets get endpointslice -l kubernetes.io/service-name=sealed-secrets-controller -o wide
```

Argo CD가 같은 클러스터에 설치되어 있다면 Application 상태도 확인합니다.

```powershell
kubectl --kubeconfig $KubeConfigFile --context $KubeContext -n argocd get application sealed-secrets
kubectl --kubeconfig $KubeConfigFile --context $KubeContext -n argocd get application sealed-secrets -o jsonpath='{.status.sync.status}{" / "}{.status.health.status}{"\n"}'
```

`sealed-secrets` namespace, Deployment, Service, Pod 또는 endpoint가 없거나 준비되지 않았다면 인증서를 가져오지 않습니다. 먼저 Argo CD Application의 `Synced / Healthy` 상태와 실제 배포 namespace를 확인합니다.

`Forbidden`이 발생하면 관리자 권한을 무조건 요청하지 말고, 대상 namespace의 Deployment·Service·Pod·endpoint를 읽을 수 있는 최소 읽기 권한을 운영 관리자에게 요청합니다.

> 이 저장소의 Argo Application destination은 `https://kubernetes.default.svc`입니다. 현재 `kubectl` context가 Argo CD가 관리하는 바로 그 클러스터인지 별도로 확인합니다.

## 3. `kubeseal` 확인

```powershell
kubeseal --version
kubectl version --client
```

이 저장소의 CI는 `.gitlab-ci.yml`에서 `kubeseal` v0.38.1 Linux amd64 아카이브와 검토된 SHA-256을 고정합니다. CI 버전을 올릴 때는 새 릴리스의 checksum/signature를 검토하고 CI의 고정값을 함께 변경해야 합니다. 로컬 클라이언트도 우선 `0.38.1`을 사용하고, 버전을 바꿀 때는 Controller와의 호환성을 확인합니다.

## 4. 공개 인증서 가져오기

`kubeseal --fetch-cert`는 Kubernetes API에 접속하므로 `--kubeconfig`와 `--context`를 명시합니다. 이 명령은 named Service의 첫 번째 포트를 통해 Service proxy endpoint를 사용합니다. 따라서 Service를 읽는 권한 외에 클러스터 RBAC 정책에 따라 `services/proxy`의 `get` 권한이 필요할 수 있습니다. `Forbidden`이 계속되면 관리자 권한 전체를 요청하기보다 이 정확한 subresource 권한을 확인합니다. `--sealed-secret-file` (`-w`)를 사용하면 셸의 `>` 리다이렉션보다 부분 출력 파일을 줄일 수 있지만, 최종 파일 교체 오류까지 모든 버전에서 감지한다고 가정하지 않습니다.

### Windows PowerShell

`$KubeConfigFile`, `$KubeContext`는 1단계에서 설정한 값을 사용합니다. 아래의
`$CertificatePath`를 기본 저장소 경로로 둘 수 있지만, `.secrets`가 실제로 Git에서
무시되는지 확인해야 합니다. `git check-ignore`가 실패하면 아래 값을 저장소 외부의
기존 암호화 절대 경로로 바꾸고, 그 경로를 fetch·검증·등록 단계에서 계속 사용합니다.

```powershell
$CertificatePath = Join-Path (Get-Location) '.secrets\sealed-secrets.crt'
$RepositoryCertificatePath = [IO.Path]::GetFullPath(
  (Join-Path (Get-Location) '.secrets\sealed-secrets.crt'))
$CertificatePath = [IO.Path]::GetFullPath($CertificatePath)

if ($CertificatePath -eq $RepositoryCertificatePath) {
  git check-ignore -v -- .secrets/sealed-secrets.crt
  if ($LASTEXITCODE -ne 0) { throw 'Use an ignored repository path or replace CertificatePath with an external encrypted path' }
} else {
  if (-not [IO.Path]::IsPathFullyQualified($CertificatePath)) {
    throw 'External certificate path must be absolute'
  }
  if (-not (Test-Path -LiteralPath (Split-Path -Parent $CertificatePath) -PathType Container)) {
    throw 'External certificate directory must already exist and be access-controlled'
  }
}

$CertificateDirectory = Split-Path -Parent $CertificatePath
$TempCert = Join-Path $CertificateDirectory ('.sealed-secrets-cert.' + [guid]::NewGuid().ToString('N') + '.tmp')
New-Item -ItemType Directory -Force $CertificateDirectory | Out-Null
try {
  kubeseal `
    --kubeconfig $KubeConfigFile `
    --context $KubeContext `
    --controller-name sealed-secrets-controller `
    --controller-namespace sealed-secrets `
    --fetch-cert `
    --sealed-secret-file $TempCert
  if ($LASTEXITCODE -ne 0) { throw "kubeseal failed with exit code $LASTEXITCODE" }

  if (-not (Test-Path -LiteralPath $TempCert -PathType Leaf)) { throw 'Certificate file was not created' }
  $RawCert = Get-Content -LiteralPath $TempCert -Raw
  if ([string]::IsNullOrWhiteSpace($RawCert)) { throw 'Certificate file is empty' }
  if ($RawCert -notmatch '(?s)\A-----BEGIN CERTIFICATE-----\r?\n.+?\r?\n-----END CERTIFICATE-----\r?\n?\z') { throw 'Invalid certificate PEM boundaries' }
  if ($RawCert -match 'PRIVATE KEY') { throw 'Private key material detected; discard this file' }

  Move-Item -LiteralPath $TempCert -Destination $CertificatePath -Force
} finally {
  Remove-Item -LiteralPath $TempCert -Force -ErrorAction SilentlyContinue
}
```

### Git Bash 또는 WSL

`KUBECONFIG_FILE`, `KUBE_CONTEXT`는 1단계에서 설정한 값을 사용합니다. 저장할
경로를 먼저 지정하고, 저장소 안의 경로라면 해당 파일이 실제로 Git에서 무시되는지
확인합니다. `git check-ignore`가 실패하면 저장소 외부의 기존 암호화 절대 경로를
사용하고, 그 경로를 `CERT_PATH`에 그대로 유지합니다.

```bash
set -eu
CERT_PATH="${CERT_PATH:-.secrets/sealed-secrets.crt}"
if git check-ignore -q -- "$CERT_PATH"; then
  : # The ignored repository-local path is acceptable.
else
  case "$CERT_PATH" in
    /*) : ;;
    *) printf '%s\n' 'Use an ignored path or an external absolute encrypted path' >&2; exit 1 ;;
  esac
fi
CERT_DIR="$(dirname "$CERT_PATH")"
TEMP_CERT="$CERT_DIR/.sealed-secrets-cert.$$.tmp"
cleanup() { rm -f "$TEMP_CERT"; }
trap cleanup EXIT INT TERM
mkdir -p "$CERT_DIR"

kubeseal \
  --kubeconfig "$KUBECONFIG_FILE" \
  --context "$KUBE_CONTEXT" \
  --controller-name sealed-secrets-controller \
  --controller-namespace sealed-secrets \
  --fetch-cert \
  --sealed-secret-file "$TEMP_CERT"

[ -s "$TEMP_CERT" ]
PEM_BEGIN="$(sed -n '/[^[:space:]]/p' "$TEMP_CERT" | sed -n '1p')"
PEM_END="$(sed -n '/[^[:space:]]/p' "$TEMP_CERT" | sed -n '$p')"
[ "$PEM_BEGIN" = '-----BEGIN CERTIFICATE-----' ]
[ "$PEM_END" = '-----END CERTIFICATE-----' ]
! grep -q 'PRIVATE KEY' "$TEMP_CERT"

mv -f "$TEMP_CERT" "$CERT_PATH"
trap - EXIT INT TERM
```

명령이 `service not found`로 실패하면 이름을 임의로 바꾸어 반복하지 말고, 2단계에서 확인한 실제 Service 이름과 namespace를 사용합니다. 기본 namespace를 사용하는 bare `kubeseal --fetch-cert`는 이 저장소 설정에 사용하지 않습니다.

## 5. GitLab File 변수에 등록

GitLab에서 다음 위치로 이동합니다.

```text
lime985340/gitops
→ Settings
→ CI/CD
→ Variables
```

처음 등록하는 경우 `Add variable`, 이미 만든 Placeholder 항목이 있으면 `Edit variable`을 선택합니다.

| 항목 | 설정 |
| --- | --- |
| Key | `SEALED_SECRETS_CERT` |
| Type | `File` |
| Value | fetch 단계에서 정의한 `$CertificatePath`/`$CERT_PATH` 파일의 전체 PEM 내용 |
| Environment scope | 단일 클러스터가 모든 대상 namespace를 담당할 때만 `*` |
| Protected | 실행할 ref가 Protected일 때만 활성화 |
| Masked | multiline 공개 PEM이므로 설정하지 않음 |

Registry 인증은 별도 JSON File 변수를 사용하지 않습니다. `GITLAB_REGISTRY_USERNAME`
및 `GITLAB_REGISTRY_TOKEN`을 일반 Variable로 등록하면 CI가 Docker config와 `auth`를
내부에서 생성합니다.

Value에는 파일 경로가 아니라 PEM 파일의 전체 내용을 입력합니다. 시작·끝 줄을 포함하되, Markdown 코드 펜스는 넣지 않습니다. 이 Job은 GitLab `environment:`를 선언하지 않고 dev/prod 네 개 namespace를 한 번에 처리하므로, `Environment scope: *`는 모든 실행 pipeline이 동일하게 명시된 단일 cluster를 대상으로 할 때만 사용합니다. 여러 cluster를 branch별로 사용한다면 environment-specific 변수만 추가하는 것으로는 충분하지 않으며, Job에 명시적 `environment:` 또는 branch-to-cluster 매핑을 먼저 설계해야 합니다. Protected 변수는 Protected ref에서만 전달됩니다.

잘못된 입력:

```text
C:\path\to\sealed-secrets.crt
```

올바른 형식:

```text
-----BEGIN CERTIFICATE-----
...
-----END CERTIFICATE-----
```

GitLab File 변수는 Job 실행 시 임시 파일을 만들고, CI 변수에는 그 파일 경로를 제공합니다. 저장소의 `ci/seal-secrets.sh`는 그 경로를 `kubeseal --cert "$SEALED_SECRETS_CERT"`에 전달합니다.

## 6. 클러스터를 변경하지 않는 오프라인 검증

`kubeseal --cert`는 인증서 파일만 읽으므로 Kubernetes API에 접속하지 않습니다. 실제 Secret 값을 사용하지 않고 임시 문자열 `ok`만 검증합니다. 아래 명령은 앞 단계에서 정의한 `$CertificatePath`를 사용하며, 인증서 경로를 다시 하드코딩하지 않습니다.

### PowerShell

```powershell
$Plain = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
$Sealed = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
try {
  @"
apiVersion: v1
kind: Secret
metadata:
  name: certificate-check
  namespace: default
type: Opaque
stringData:
  check: ok
"@ | Set-Content -LiteralPath $Plain -Encoding utf8

  kubeseal --cert $CertificatePath --secret-file $Plain --sealed-secret-file $Sealed --format yaml
  if ($LASTEXITCODE -ne 0) { throw "kubeseal failed with exit code $LASTEXITCODE" }
  $result = Get-Content -LiteralPath $Sealed -Raw
  if ($result -notmatch '(?m)^kind: SealedSecret$' -or $result -notmatch '(?ms)^encryptedData:\s*\r?\n\s+\S') { throw 'SealedSecret output is incomplete' }
} finally {
  Remove-Item -LiteralPath $Plain, $Sealed -Force -ErrorAction SilentlyContinue
}
```

### Git Bash 또는 WSL

아래에서도 fetch 단계에서 사용한 동일한 `CERT_PATH`를 사용합니다. 외부 절대
경로를 선택했다면 이 값을 그 경로로 다시 지정하고 저장소 상대 경로로 덮어쓰지
않습니다.

```bash
set -eu
: "${CERT_PATH:?Set CERT_PATH to the verified certificate path from step 4}"
PLAIN="$(mktemp)"
SEALED="$(mktemp)"
cleanup() { rm -f "$PLAIN" "$SEALED"; }
trap cleanup EXIT INT TERM
cat > "$PLAIN" <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: certificate-check
  namespace: default
type: Opaque
stringData:
  check: ok
EOF

kubeseal \
  --cert "$CERT_PATH" \
  --secret-file "$PLAIN" \
  --sealed-secret-file "$SEALED" \
  --format yaml
grep -q '^kind: SealedSecret$' "$SEALED"
awk '/^encryptedData:[[:space:]]*$/ { in_data=1; next } in_data && /^[^[:space:]]/ { exit 1 } in_data && /^[[:space:]]+[^[:space:]]/ { found=1; exit } END { exit !found }' "$SEALED"
```

이 검증은 `kubectl apply`를 실행하지 않으므로 클러스터에 리소스를 만들지 않습니다.

## 7. 등록 후 확인과 파이프라인 조건

변수 저장만으로 파이프라인이 실행되지는 않습니다. GitLab 변수 목록에서 다음을 확인합니다.

- `SEALED_SECRETS_CERT`가 `File` 타입인지
- 값이 `PLACEHOLDER_REPLACE_ME`로 남아 있지 않은지
- Protected 설정이 실행할 브랜치 정책과 맞는지
- 인증서 파일과 임시 테스트 파일이 로컬에서 삭제되었는지

`seal:workload-secrets`에는 인증서 외에도 다음 값이 필요합니다.

- `GITLAB_REGISTRY_USERNAME` - 서비스 이미지 프로젝트에 접근하는 Registry username
- `GITLAB_REGISTRY_TOKEN` - 서비스 이미지 프로젝트에 `read_registry` 권한이 있는 token
- `ATMO_API_DEV_DB_ENV`
- `ATMO_API_DEV_JWT_ENV`
- `ATMO_API_DEV_OAUTH_ENV`
- `ATMO_API_DEV_PUBLICDATA_ENV`
- `ATMO_API_PROD_DB_ENV`
- `ATMO_API_PROD_JWT_ENV`
- `ATMO_API_PROD_OAUTH_ENV`
- `ATMO_API_PROD_PUBLICDATA_ENV`

GitOps 저장소 자체에 대한 CI Push는 GitLab 사전 정의 `CI_JOB_TOKEN`을 사용하므로
`GITOPS_PUSH_TOKEN`과 `GITOPS_PUSH_TOKEN_USER`는 이 Job에 등록하지 않습니다.
이 변수들은 서비스 저장소가 새 image tag를 GitOps 저장소에 반영할 때 사용하는
별도 Group 변수입니다. 실제 값을 모두 등록하고 대상 Protected branch를 확인한
뒤에만 sealing을 실행합니다.

Sealing 실행은 일반 Pipeline 변수 `UPDATE_SECRETS`를 사용하지 않습니다. GitLab의
`Build` → `Pipelines` → `New pipeline`에서 `feature/clean-gitops-layout`을
선택하고 `Inputs`의 boolean `update_secrets`를 `true`로 설정한 뒤 Pipeline을
실행하고 `seal:workload-secrets` 수동 Job을 시작합니다. Secret 값은 Pipeline
입력 화면이 아니라 GitLab CI/CD Variables에만 둡니다. `spec:inputs`가 반영된
최신 CI 설정인데도 Inputs가 비어 있으면 feature branch의 YAML이 로드되었는지
확인하며, 일반 Pipeline 변수 override 권한을 완화하지 않습니다.

실제 값과 Protected ref 정책을 확인하기 전에는 sealing을 실행하지 않습니다.


## 문제 해결과 갱신

### `kubeseal: command not found`

공식 릴리스에서 호환되는 `kubeseal` CLI를 설치하고 새 셸에서 다음을 다시 확인합니다.

```powershell
kubeseal --version
```

### `service not found` 또는 `Forbidden`

1. 같은 셸에서 명시적인 `--kubeconfig`와 `--context`로 API 서버를 확인합니다.
2. 대상 namespace의 Deployment, Service, Pod, endpoint 상태를 확인합니다.
3. `--controller-name`에는 실제 Service 이름을, `--controller-namespace`에는 실제 namespace를 지정합니다.
4. 필요한 경우 최소 읽기 권한을 운영 관리자에게 요청합니다.

### 인증서로 생성한 SealedSecret이 복호화되지 않음

잘못된 클러스터의 인증서를 사용했거나 Controller 키가 교체된 경우일 수 있습니다.

1. 대상 클러스터와 Controller를 다시 확인합니다.
2. 이 문서 4단계의 명시적인 `kubeseal --fetch-cert` 명령으로 인증서를 다시 가져옵니다.
3. GitLab의 `SEALED_SECRETS_CERT` File 변수 값을 교체합니다.
4. 기존 ciphertext를 인증서 파일만으로 새 인증서에 다시 암호화할 수는 없습니다. Controller가 이전 키를 보유한 경우의 re-encrypt 절차 또는 Private Key 복구를 먼저 검토하고, 이전 키를 잃은 경우 원래 평문 File 변수로 SealedSecret을 다시 생성합니다.

Controller Private Key는 GitLab 변수나 Git에 업로드하지 않습니다.

## 정리

GitLab 등록 후 로컬 인증서 파일을 삭제하고 작업 트리 상태를 확인합니다.

```powershell
Remove-Item -LiteralPath $CertificatePath -Force -ErrorAction SilentlyContinue
git status --short
```

Git Bash/WSL에서는 fetch 단계에서 정의한 `$CERT_PATH`를 사용합니다:

```bash
rm -f "$CERT_PATH"
git status --short
```

이 문서의 명령은 인증서 취득과 오프라인 검증을 위한 것입니다. `kubeseal --fetch-cert`만 Kubernetes API에 접근하며, `kubeseal --cert` 검증은 클러스터를 변경하지 않습니다.

## 참고

- [`argocd/applications/sealed-secrets.yaml`](../argocd/applications/sealed-secrets.yaml)
- [`ci/seal-secrets.sh`](../ci/seal-secrets.sh)
- [`sealed-secrets-recovery.md`](sealed-secrets-recovery.md)
- [Sealed Secrets 공식 문서](https://github.com/bitnami-labs/sealed-secrets)

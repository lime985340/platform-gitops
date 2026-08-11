# GitOps

이 저장소는 Argo CD가 읽는 Kubernetes 매니페스트를 관리합니다. 현재 브랜치는
Sealed Secrets를 사용해 민감한 값을 Git에 암호화된 형태로 저장하는 구성을
사용합니다.

## 현재 구성

```text
SealedSecret(암호화된 값)
  -> Sealed Secrets controller
  -> Kubernetes Secret
  -> workload Pod
```

Argo CD는 `argocd/applications/sealed-secrets.yaml`을 통해 Sealed Secrets
controller를 설치합니다. 실제 애플리케이션은 `argocd/applicationsets/workloads.yaml`이
`workloads/*/*/environments/*` 디렉토리를 찾아 배포합니다.

현재 저장소에는 다음 Secret의 placeholder 파일이 들어 있습니다.

- Atmo API: DB, JWT, OAuth, 공공데이터, GitLab registry
- Atmo Web: GitLab registry
- Argo CD: GHCR repository credentials
- cert-manager: DNS API token

placeholder의 `spec.encryptedData`가 비어 있으므로, 값을 채우기 전까지 해당
Secret을 필요로 하는 Pod가 정상 실행되지 않는 것은 예상된 상태입니다.

## 필요한 도구

Secret을 생성하는 PC에 다음 도구가 필요합니다.

- `git`: 암호화된 매니페스트 커밋 및 푸시
- `kubectl`: 로컬 dry-run Secret 생성과 클러스터 확인
- `kubeseal`: SealedSecret 생성
- 대상 Kubernetes 클러스터에 접근할 수 있는 kubeconfig

Windows에서는 다음 명령으로 `kubectl`을 설치할 수 있습니다.

```powershell
winget install -e --id Kubernetes.kubectl
```

`kubeseal`은 [공식 릴리스](https://github.com/bitnami-labs/sealed-secrets/releases)에서
운영체제와 아키텍처에 맞는 파일을 내려받아 `PATH`에 추가합니다.

설치를 확인합니다.

```powershell
kubectl version --client
kubeseal --version
```

## Secret 값 추가 또는 변경

평문 값은 저장소 밖의 `.secrets` 디렉토리에 둡니다. 이 디렉토리는
`.gitignore`에 등록되어 있으므로 커밋하지 않습니다.

예를 들어 개발 DB Secret의 로컬 입력 파일을 만듭니다.

```text
.secrets/atmo-db-dev.env
```

파일에는 애플리케이션이 요구하는 전체 키를 넣습니다.

```env
SPRING_DATASOURCE_URL=jdbc:postgresql://db.example.com:5432/atmo
SPRING_DATASOURCE_USERNAME=atmo
SPRING_DATASOURCE_PASSWORD=REPLACE_WITH_REAL_VALUE
SPRING_REDIS_HOST=redis.example.com
SPRING_REDIS_PORT=6379
```

controller가 설치된 클러스터에서 공개 인증서를 한 번 가져옵니다.

```powershell
New-Item -ItemType Directory -Force .secrets | Out-Null
kubeseal --fetch-cert `
  --controller-name sealed-secrets `
  --controller-namespace sealed-secrets `
  | Set-Content -Encoding utf8 .secrets/sealed-secrets.crt
```

로컬 dry-run Secret을 만들고 바로 암호화합니다. `--dry-run=client`이므로
이 명령 자체는 클러스터에 평문 Secret을 생성하지 않습니다.

```powershell
kubectl create secret generic atmo-db-secret `
  --namespace atmo-api-dev `
  --from-env-file .secrets/atmo-db-dev.env `
  --dry-run=client -o yaml |
kubeseal `
  --cert .secrets/sealed-secrets.crt `
  --format yaml |
Set-Content -Encoding utf8 `
  workloads/atmo/api/environments/dev/sealedsecret-db.yaml
```

대상 Secret 이름, namespace, 출력 파일만 바꾸어 JWT·OAuth·registry 등의
다른 Secret에도 같은 방법을 사용합니다. 이미 있는 값을 변경할 때도 로컬
`.env` 파일만 수정한 후 같은 명령을 다시 실행해 기존 `sealedsecret-*.yaml`을
덮어씁니다. `spec.encryptedData`는 직접 수정하지 않습니다.

변경 후에는 암호화된 YAML만 커밋하고 푸시합니다.

```powershell
git diff -- workloads/atmo/api/environments/dev/sealedsecret-db.yaml
git add workloads/atmo/api/environments/dev/sealedsecret-db.yaml
git commit -m "update dev database sealed secret"
git push
```

Argo CD가 변경된 `SealedSecret`을 적용하면 controller가 같은 이름의
Kubernetes Secret을 갱신합니다. 애플리케이션이 시작 시에만 값을 읽는다면
해당 Deployment를 재시작해야 합니다.

## 보안 규칙

- 평문 `.env`, 평문 `Secret` YAML, 비밀번호, 토큰을 커밋하지 않습니다.
- Git에는 `spec.encryptedData`가 들어 있는 SealedSecret만 커밋합니다.
- controller의 private key 백업은 저장소 밖에서 별도로 보호합니다.
- 환경과 namespace마다 별도의 SealedSecret을 사용합니다.

공식 문서:

- [Kubernetes 도구 설치](https://kubernetes.io/docs/tasks/tools/)
- [Sealed Secrets 프로젝트](https://github.com/bitnami-labs/sealed-secrets)

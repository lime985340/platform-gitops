# Ontology ASAL Agent 운영 보안 설정

이 문서는 `ontology-asal-agent`를 운영 환경에 배포할 때 필요한 GraphDB 인증,
애플리케이션 실행 Secret, Container Registry 인증, SealedSecret 처리 절차를
정의합니다.

실제 비밀번호, API Key, Token, GraphDB license, Controller Private Key는 이
문서나 Git 저장소에 기록하지 않습니다. GitLab CI/CD Variables와 승인된 Secret
관리 절차를 통해서만 전달합니다.

## 1. 현재 테스트 구성과 운영 구성

현재 `main`의 GraphDB Application은 테스트 부트스트랩을
위해 다음처럼 설정되어 있습니다.

```yaml
security:
  enabled: false

service:
  type: ClusterIP

ingress:
  enabled: false
```

따라서 현재 테스트 구성에서는 GraphDB username/password가 필요하지 않습니다.
GraphDB는 사용자 클러스터 내부에서 Argo CD가 Helm Chart로 배포하며, 서비스 주소는
다음과 같습니다.

```text
http://graphdb.graphdb.svc.cluster.local:7200
```

운영 구성에서는 다음 원칙을 적용합니다.

- GraphDB는 운영 Kubernetes 클러스터에 Argo CD/GitOps로 배포합니다.
- 애플리케이션이 사용하는 계정은 GraphDB 관리자 계정과 분리합니다.
- API는 `reader` 계정만 사용합니다.
- 온톨로지 적재 Migration Job은 별도의 `writer` 계정을 사용합니다.
- GraphDB license와 초기 보안 설정은 SealedSecret 또는 외부 Secret 관리 체계로
  전달합니다.
- Google 로그인이나 GitLab 로그인 정보는 GraphDB 계정으로 사용하지 않습니다.

## 2. 계정 설계

운영에서는 최소한 다음 계정을 분리합니다.

| 계정 | 사용 위치 | 권한 |
| --- | --- | --- |
| GraphDB bootstrap/admin | 초기 보안 설정과 사용자 관리 | 초기화에만 사용, 애플리케이션에 전달하지 않음 |
| `asal-agent-dev-reader` | Dev API | `asal-agent` repository query/read |
| `asal-agent-prod-reader` | Prod API | `asal-agent` repository query/read |
| `asal-agent-dev-writer` | Dev Migration Job | ontology/shapes 적재 및 갱신 |
| `asal-agent-prod-writer` | Prod Migration Job | ontology/shapes 적재 및 갱신 |

계정명은 예시이며 실제 계정명은 조직 정책에 맞춰 정합니다. 비밀번호는 password
manager 등에서 충분히 긴 랜덤 값으로 생성합니다. Google 계정 비밀번호, GitLab
비밀번호, GitLab PAT를 GraphDB 비밀번호로 재사용하지 않습니다.

## 3. GitLab 변수

### 3.1 서비스 저장소 CI에서 상속하는 Group 변수

`ontology-asal-agent-api`와 `ontology-asal-agent-web`의 이미지 빌드 후 GitOps
이미지 태그를 갱신하는 job은 다음 Group 변수를 사용합니다.

| 변수 | 타입 | 목적 |
| --- | --- | --- |
| `GITOPS_BRANCH` | Variable | 현재 `main` |
| `GITOPS_PUSH_TOKEN` | Variable | GitOps 저장소 `write_repository` 토큰 |
| `GITOPS_PUSH_TOKEN_USER` | Variable | 해당 토큰의 사용자명 |

세 변수는 Protected로 관리하고, 실행 브랜치/태그도 Protected 정책에 맞춰야 합니다.
이 변수는 GitOps의 애플리케이션 실행 Secret이 아닙니다.

### 3.2 GitOps 프로젝트 변수

GitOps 프로젝트의 수동 `seal:workload-secrets` job은 다음 값을 사용합니다.

| 변수 | 타입 | 운영 필요 여부 | 용도 |
| --- | --- | --- | --- |
| `SEALED_SECRETS_CERT` | File | 필수 | Sealed Secrets Controller 공개 인증서 |
| `GITLAB_REGISTRY_USERNAME` | Variable | 필수 | API/Web 이미지 Pull 계정 |
| `GITLAB_REGISTRY_TOKEN` | Variable | 필수 | API/Web 이미지 `read_registry` 토큰 |
| `ONTOLOGY_ASAL_AGENT_DEV_ENV` | File | Dev 배포 시 필수 | Dev API 런타임 Secret |
| `ONTOLOGY_ASAL_AGENT_PROD_ENV` | File | Prod 배포 시 필수 | Prod API 런타임 Secret |
| `GRAPHDB_LICENSE_FILE` | File | RDF 쓰기 시 필수 | GraphDB license 파일 |

`GITLAB_REGISTRY_USERNAME`과 `GITLAB_REGISTRY_TOKEN`은 `lime985340` Group에
공통으로 등록하는 것을 권장합니다. 중복된 프로젝트 변수가 있으면 Group 값이
가려질 수 있으므로 하나의 기준만 사용합니다.

GitLab이 실행 중 자동으로 제공하는 `CI_JOB_TOKEN`은 직접 변수로 만들지 않습니다.
GitOps 프로젝트의 Job Token repository push 허용 설정과 대상 Protected branch
정책을 함께 확인해야 합니다.

### 3.3 API 런타임 File 변수 형식

Dev와 Prod File 변수에는 환경별 실제 값을 한 줄에 하나씩 입력합니다.

```env
LLM_API_KEY=<실제 LLM provider API key>
TRIPLESTORE_USERNAME=<해당 환경의 GraphDB reader 계정>
TRIPLESTORE_PASSWORD=<해당 환경의 GraphDB reader 비밀번호>
```

현재 API ConfigMap에서 다음 값들은 이미 관리하므로 런타임 File 변수에 반복해서
넣지 않습니다.

- `LLM_BASE_URL`
- `LLM_MODEL`
- `ONTOLOGY_SOURCE`
- `TRIPLESTORE_QUERY_URL`
- `TRIPLESTORE_UPDATE_URL`
- `TRIPLESTORE_ONTOLOGY_GRAPH`
- `TRIPLESTORE_SHAPES_GRAPH`
- timeout 및 local fallback 설정

GraphDB 보안이 활성화되면 `TRIPLESTORE_USERNAME`과
`TRIPLESTORE_PASSWORD`에는 API용 reader 계정을 입력합니다. 관리자 계정이나
Migration Job의 writer 계정을 API에 넣지 않습니다.

## 4. GraphDB 보안 활성화 절차

GraphDB를 노트북에서 별도로 실행하거나 Google 계정으로 로그인하는 방식이
아닙니다. 운영 Kubernetes 클러스터의 GraphDB Helm/Argo CD 설정을 GitOps로
변경합니다.

1. 운영 GraphDB 계정 정책을 정하고 bootstrap/admin, reader, writer 계정을
   생성할 준비를 합니다.
2. GraphDB Helm Chart가 요구하는 초기 사용자 설정(`users.js` 등)과 provisioning
   인증 정보를 Secret으로 준비합니다. Chart 버전에 맞는 키 이름과 형식을
   사용합니다.
3. `argocd/applications/graphdb.yaml`의 운영 overlay에서 GraphDB security를
   활성화합니다.
4. 초기 사용자 Secret, GraphDB license, API 런타임 File 변수를 평문이 아닌
   GitLab File Variable/승인된 Secret 저장소에 등록합니다.
5. GitOps 프로젝트의 `Build` → `Pipelines` → `New pipeline`에서
   `main`을 선택하고 `update_secrets=true` 입력으로
   수동 sealing job을 실행합니다.
6. CI가 `kubeseal`로 대상 Namespace와 Secret 이름에 맞는 SealedSecret을
   생성하고, 암호화된 YAML만 GitOps 브랜치에 Push합니다.
7. Argo CD 동기화 후 GraphDB Pod, API Deployment, Migration Job 상태를
   확인합니다.

초기 bootstrap/admin 인증 정보는 GraphDB 사용자 초기화용으로만 사용하고,
API의 `ONTOLOGY_ASAL_AGENT_*_ENV`에 넣지 않습니다.

## 5. Reader/Writer 연결 주의사항

현재 API Deployment는 `ontology-asal-agent-secrets`를 읽을 수 있도록 구성되어
있습니다. 반면 현재 온톨로지 Migration Job은 ConfigMap만 읽고 있어, GraphDB
보안을 활성화하기 전에 writer Secret 연결을 별도로 추가해야 합니다.

운영 보안 활성화 전에 다음을 구현·검증합니다.

- Dev/Prod Migration Job에 각 환경의 writer Secret을 `envFrom` 또는 명시적
  Secret 참조로 연결
- writer 계정이 `asal-agent` repository에 필요한 write/update 권한을 갖는지 확인
- API reader 계정에는 write/admin 권한을 부여하지 않음
- Secret 이름과 Namespace를 Dev/Prod별로 분리
- Migration Job 로그에 username/password가 출력되지 않는지 확인

writer Secret 연결 없이 GraphDB 보안만 켜면 API query는 동작할 수 있지만,
`domain.ttl`과 `shapes.ttl` 적재는 인증 실패합니다.

## 6. License와 데이터 검증

GraphDB UI와 repository 목록은 license가 없어도 일부 확인할 수 있지만, 현재
구성에서는 RDF transaction과 온톨로지 적재에 유효한 license가 필요합니다.

`GRAPHDB_LICENSE_FILE`은 실제 license 파일의 내용으로 등록하고, CI가 생성한
암호화 결과만 `platform/graphdb/sealed-secret.yaml`에 저장합니다. Git에는 license
원문을 저장하지 않습니다.

클러스터 내부 확인 예시는 다음과 같습니다.

```bash
kubectl -n graphdb get pods
kubectl -n graphdb port-forward svc/graphdb 7200:7200
```

그 다음 브라우저에서 `http://localhost:7200`을 열고 `asal-agent` repository를
선택합니다. SPARQL 화면에서 다음 query로 데이터 존재 여부를 확인합니다.

```sparql
SELECT (COUNT(*) AS ?triples)
WHERE {
  ?s ?p ?o
}
```

운영 보안이 활성화된 후에는 GraphDB reader 계정으로 query가 성공하는지, writer
계정으로 Migration Job이 성공하는지 각각 확인합니다.

## 7. 금지사항

- Google/GitLab 로그인 비밀번호를 GraphDB 계정으로 사용하지 않음
- `admin` 계정을 API 또는 Migration Job에 전달하지 않음
- `.env`, kubeconfig, PAT, Registry token, GraphDB license 원문을 Git에 커밋하지 않음
- SealedSecret Controller Private Key를 GitLab 변수나 Git에 저장하지 않음
- File Variable 값을 Pipeline 입력값이나 로그로 출력하지 않음
- 보안 비활성 테스트 구성을 운영에 그대로 승격하지 않음


# Istio Ambient Mesh 도입 검토

## 결론

현재 GitOps에는 Istio Ambient의 공통 기반을 추가하고, 생성되는 애플리케이션
Namespace를 Ambient에 자동 등록하도록 구성했습니다. 다만 실제 클러스터 반영은
이 Feature 브랜치를 `main`에 병합한 뒤에 시작됩니다.

Ambient는 노드당 L4 `ztunnel`을 사용해 mTLS, workload identity, L4 인가와
텔레메트리를 제공하고, HTTP 라우팅·L7 인가·HTTP 관측이 필요할 때만 Namespace
또는 workload 단위의 Envoy waypoint를 추가하는 구조입니다. 따라서 현재의
`API -> CLIProxyAPI:8317` 접근 제한만으로는 waypoint가 필요하지 않습니다.

참고: [Ambient overview](https://istio.io/latest/docs/ambient/overview/),
[Ambient data plane](https://istio.io/latest/docs/ambient/architecture/data-plane/)

## 현재 GitOps 상태

- `argocd/applications` 아래에 `istio-base`, `istiod`, `istio-cni`, `ztunnel`을
  공식 Istio Helm Chart `1.29.5`로 관리하는 Application이 있습니다.
- `argocd/applicationsets/platform.yaml`의 Platform ApplicationSet은
  `platform/policies`와 Cloudflare 경로만 생성합니다.
- `argocd/applicationsets/workloads.yaml`은 `main`의
  `workloads/*/*/environments/*`를 동기화하며, `managedNamespaceMetadata`로
  각 생성 Namespace에 `istio.io/dataplane-mode=ambient`를 붙입니다.
- `platform/policies`는 Cilium `CiliumClusterwideNetworkPolicy`를 사용하고,
  Ambient HBONE 포트·kubelet health probe·Istio control plane 통신 예외를
  별도 정책으로 관리합니다.
- `workloads/cli-proxy/api`는 공용 CLI Proxy API workload이고,
  `workloads/ontology-asal-agent/api`는 애플리케이션 workload입니다.
- CLI Proxy API에는 Dev/Prod 모두 `PeerAuthentication(STRICT)`와
  `AuthorizationPolicy`가 추가되어 해당 환경의 Ontology API ServiceAccount만
  포트 `8317`로 호출할 수 있게 했습니다.
- `kiali-operator` Helm Application과 `istio-system`의 Kiali CR을 추가해
  읽기 전용 Token 인증 기반의 웹 대시보드를 제공합니다. Kiali는 기존
  Prometheus와 Grafana를 클러스터 내부 주소로 사용합니다.

Istio의 `base` Chart가 CRD를 설치하고, `istiod`·Istio CNI·`ztunnel`이 순서대로
배포됩니다. Gateway와 waypoint는 아직 추가하지 않았으므로 외부 진입은 기존
Traefik 구성을 유지하고, 현재 범위는 workload 간 Ambient 보안 통신입니다.

## Cilium과의 관계

Istio는 CNI가 아니며 Kubernetes NetworkPolicy를 대체하거나 우회하지 않습니다.
Ambient 트래픽은 workload 간 HBONE 터널로 전달되고 대상 측에서 원래 포트로
프록시되므로, 기존 CNI 정책이 터널 포트와 health probe를 막지 않는지 확인해야
합니다.

특히 현재 GitOps에는 non-system Pod에 대한 Cilium default-deny egress가 있고,
CLIProxyAPI에는 포트 단위의 ingress allow-list를 추가했습니다. Ambient를 켜면
다음 항목을 다시 검증해야 합니다.

- Cilium 정책이 일반 서비스 포트뿐 아니라 Ambient의 HBONE 경로도 허용하는지
- Cilium default-deny 환경에서 kubelet health probe가 계속 성공하는지
- Cilium L7 정책과 Istio waypoint L7 정책을 중복 적용하지 않는지
- Hubble에서 실제 source identity와 ztunnel 경로가 의도대로 보이는지

Istio 공식 문서는 Ambient와 CNI NetworkPolicy를 함께 사용할 때 HBONE 포트와
health probe 예외를 확인하도록 안내합니다. Cilium 공식 통합 문서는 Istio와
함께 사용할 때 Cilium의 `cni.exclusive=false`, 그리고 kube-proxy replacement
구성에 따른 `socketLB.hostNamespaceOnly=true` 설정을 확인하도록 안내합니다.

참고: [Ambient and Kubernetes NetworkPolicy](https://istio.io/latest/docs/ambient/usage/networkpolicy/),
[Istio and Cilium integration](https://docs.cilium.io/en/latest/network/servicemesh/istio/)

## 현재 적용한 GitOps 변경 범위

Istio Ambient는 CLIProxyAPI workload 안에 sidecar를 넣는 방식이 아닙니다. GitOps의
Platform 영역에 별도 Helm Application을 추가하는 작업입니다.

1. `istio-system` Namespace와 Platform AppProject 허용 범위를 추가했습니다.
2. 공식 Helm Chart를 `1.29.5`로 고정했습니다. CI가 대상으로 삼는 Kubernetes
   `1.31`과의 호환성을 고려한 선택이며, 실제 클러스터 버전은 병합 전에 확인해야
   합니다.
3. `base`, `istiod(profile=ambient)`, `cni(profile=ambient)`, `ztunnel`을
   각각 Argo CD Application으로 관리합니다.
4. Workload ApplicationSet이 생성하는 모든 애플리케이션 Namespace를
   `istio.io/dataplane-mode=ambient`로 자동 등록합니다.
5. CLI Proxy API에는 mTLS `STRICT`와 Ontology API ServiceAccount 기반 L4
   `AuthorizationPolicy`를 우선 적용합니다.
6. HTTP 경로·헤더 기반 정책, HTTP telemetry, retries 또는 traffic routing이
   필요할 때만 waypoint를 추가합니다.

공식 Helm 설치 가이드는 Ambient 지원을 위해 Base CRD, Istiod, Istio CNI와
ztunnel을 분리 설치하도록 안내합니다. 운영에서는 Helm 기반 설치가 권장되므로,
도입 시 현재의 Platform ApplicationSet과 AppProject에 맞춘 별도 Argo CD
Application 구성이 필요합니다.

참고: [Install Ambient with Helm](https://istio.io/latest/docs/ambient/install/helm/),
[Add workloads to the Ambient mesh](https://istio.io/latest/docs/ambient/usage/add-workloads/),
[Configure waypoint proxies](https://istio.io/latest/docs/ambient/usage/waypoint/)

## 권장 결정

현재 Feature에서는 다음과 같이 결정했습니다.

- CLIProxyAPI 접근 제어: 현재 구현한 Cilium L3/L4 정책 유지
- Istio 설치: `1.29.5` Ambient Helm Application을 GitOps에 추가
- Namespace 등록: Workload ApplicationSet에서 생성 시 자동 등록
- 초기 범위: 모든 애플리케이션 Namespace의 Ambient 연결과 CLI Proxy API의
  mTLS/L4 identity 검증
- Waypoint: L7 요구사항이 확인될 때만 추가
- 정책 소유권: L3/L4 접근은 Cilium, Istio mTLS·Istio L7 정책은 Istio로 분리

병합 후에는 먼저 `istio-system`의 `istiod`, `istio-cni`, `ztunnel` 상태와
Namespace 라벨을 확인하고, Dev의 Ontology API → CLI Proxy API 호출 및 health
probe를 검증해야 합니다. 클러스터에 kube-proxy가 없으면 Cilium의
`kubeProxyReplacement=true`, `socketLB.hostNamespaceOnly=true`를 별도로 맞춰야
하며, Cilium과 Istio CNI의 chaining을 위해 `cni.exclusive=false`가 필요합니다.

## Kiali 접속

Kiali는 외부 Ingress를 만들지 않고 `istio-system`의 Service로만 배포합니다.
병합 및 동기화 후 다음처럼 로컬 포트 포워딩으로 접속합니다.

```bash
kubectl -n istio-system port-forward svc/kiali 20001:20001
```

브라우저에서 `http://localhost:20001/kiali`로 접속한 뒤 Kubernetes Token으로
로그인합니다. ServiceAccount 이름은 클러스터에서 확인할 수 있습니다.

```bash
kubectl -n istio-system get serviceaccount -l app=kiali
kubectl -n istio-system create token <KIALI_SERVICE_ACCOUNT>
```

Kiali는 공식 권장 방식인 Operator와 Kiali CR 조합으로 배포하며, 현재 CR은
`view_only_mode=true`로 Istio 리소스를 변경하지 못하도록 했습니다.

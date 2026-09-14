# Istio Ambient Mesh 도입 검토

## 결론

현재 GitOps의 CLIProxyAPI 접근 제어 목적만 보면 Cilium 정책으로 충분합니다.
Istio Ambient를 지금 전체 클러스터에 추가하기보다는, 운영 트래픽을 안정화한 뒤
Dev Namespace에서 단계적으로 검증하는 것을 권장합니다.

Ambient는 노드당 L4 `ztunnel`을 사용해 mTLS, workload identity, L4 인가와
텔레메트리를 제공하고, HTTP 라우팅·L7 인가·HTTP 관측이 필요할 때만 Namespace
또는 workload 단위의 Envoy waypoint를 추가하는 구조입니다. 따라서 현재의
`API -> CLIProxyAPI:8317` 접근 제한만으로는 waypoint가 필요하지 않습니다.

참고: [Ambient overview](https://istio.io/latest/docs/ambient/overview/),
[Ambient data plane](https://istio.io/latest/docs/ambient/architecture/data-plane/)

## 현재 GitOps 상태

- Istio Helm Application, `istiod`, `istio-cni`, `ztunnel`, Gateway 리소스가 없습니다.
- `argocd/applicationsets/platform.yaml`의 Platform ApplicationSet은
  `platform/policies`와 Cloudflare 경로만 생성합니다.
- `argocd/applicationsets/workloads.yaml`은 `main`의
  `workloads/*/*/environments/*`만 동기화합니다.
- `platform/policies`는 Cilium `CiliumClusterwideNetworkPolicy`를 사용합니다.
- `workloads/platform/cli-proxy-api`는 공용 플랫폼 workload이고,
  `workloads/ontology-asal-agent/api`는 애플리케이션 workload입니다.

따라서 현재 Feature의 Istio 검토는 설치 변경이 아니라 도입 조건과 영향 분석
단계입니다. Feature가 `main`에 병합되기 전까지는 실제 클러스터에 적용되지 않습니다.

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

## 도입 시 GitOps 변경 범위

Istio Ambient는 CLIProxyAPI workload 안에 sidecar를 넣는 방식이 아닙니다. GitOps의
Platform 영역에 별도 Helm Application을 추가하는 작업입니다.

1. `istio-system` Namespace와 Platform AppProject 허용 범위를 추가합니다.
2. 공식 Helm Chart를 고정 버전으로 등록합니다.
3. `base`, `istiod(profile=ambient)`, `cni(profile=ambient)`, `ztunnel`을
   별도 Argo CD Application 또는 검증 가능한 상위 구성으로 관리합니다.
4. Dev의 `ontology-asal-agent-api-dev`와
   `platform-cli-proxy-api-dev`부터 `istio.io/dataplane-mode=ambient`를
   적용합니다.
5. mTLS와 L4 `AuthorizationPolicy`만 먼저 검증합니다.
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

현재 단계에서는 다음과 같이 결정합니다.

- CLIProxyAPI 접근 제어: 현재 구현한 Cilium L3/L4 정책 유지
- Istio 설치: 지금은 추가하지 않음
- 도입 시점: Cilium 설정과 실제 클러스터 상태를 확인한 뒤 Dev에서 시범 적용
- 초기 범위: API와 Proxy의 mTLS/L4 identity 검증
- Waypoint: L7 요구사항이 확인될 때만 추가
- 정책 소유권: L3/L4 접근은 Cilium, Istio mTLS·Istio L7 정책은 Istio로 분리

새 클러스터나 기존 Cilium Helm 값이 확인되지 않은 상태에서 Istio를 바로
추가하면 CNI chaining, kube-proxy replacement, HBONE 포트, health probe 문제를
동시에 디버깅해야 합니다. 먼저 현재 Cilium 설치값과 클러스터에서 Dev API와
Proxy의 연결·readiness를 확인한 다음, 별도 Feature에서 Ambient pilot을 진행하는
것이 안전합니다.

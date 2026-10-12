# Q 인테리어 운영 연결

## 구조

기준일: 2026-10-09. `atmo-api`, `atmo-web`, 본 저장소의 기존 CI·ApplicationSet·Sealed Secrets 구성을 읽고 확장한 초기 구현입니다.

- `q-interior-api`: Spring Boot + Kotlin API, Container Registry 이미지.
- `q-interior-client`: KMP·Compose 웹·Android·iOS, 웹만 컨테이너 이미지.
- 본 저장소: 웹·API 이미지 배포 CI, Kubernetes overlay, 런타임 시크릿 sealing.
- 모바일 서명·Firebase App Distribution: `q-interior-client` 저장소의 CI.

```mermaid
flowchart LR
  Source[API · Client CI] --> Image[웹/API SHA 이미지 · 릴리스 승격]
  Image --> Trigger[GitOps downstream CI]
  Trigger --> MR[배포 MR]
  MR --> Argo[Argo CD]
  Argo --> K8s[웹 · API]
  Client[`q-interior-client` CI] --> Mobile[수동 Android/iOS 빌드 · 서명]
  Mobile --> Firebase[Firebase App Distribution]
```

Firebase는 tester 배포입니다. Play Store/App Store 정식 출시는 별도 흐름이며 현재 구현했다고 간주하지 않습니다. Argo CD는 Kubernetes의 웹·API만 동기화하고 모바일 앱 배포에는 관여하지 않습니다. 앱은 소스 저장소 CI가 해당 commit을 직접 빌드·서명해 Firebase에 배포합니다.

## 운영 경로

API 공개 경로는 `/saerom/api/v1`, 서버 내부 경로는 `/api/v1`입니다. 웹 공개 경로는 `/saerom/`입니다. Traefik이 `/saerom`을 제거하고 각 서비스로 보냅니다. Cookie path는 공개 API 경로와 일치합니다.

overlay는 `workloads/q-interior/{api,web}/environments/{dev,prod}`입니다. 기존 ApplicationSet이 자동 발견하므로 별도 앱 ApplicationSet을 만들지 않습니다. 기존 atmo와 동일하게 dev는 ingress 없이 port-forward 중심, prod는 path ingress를 준비했습니다. 실제 host는 기존 Traefik 진입점을 사용하며 새 도메인을 임의로 지정하지 않습니다.

초기 replicas는 **0**입니다. Registry secret·DB secret이 비어 있는 overlay를 실제 운영 완료로 간주하지 않습니다. 첫 배포 명령은 필요한 암호화 secret과 Neon host를 검사한 뒤 image tag 및 replicas를 바꾸는 MR을 만듭니다. 배포 MR을 병합해야 Argo CD가 실제 반영합니다.

## 본 저장소에 설정할 변수

실제 값을 문서나 채팅에 넣지 않습니다. 아래는 이름과 전달 계약입니다.

| 이름 | 형태 | 사용처 |
| --- | --- | --- |
| `Q_INTERIOR_API_DEV_ENV` / `Q_INTERIOR_API_PROD_ENV` | File, protected | datasource URL·username·password를 kubeseal로 암호화 |
| `Q_INTERIOR_NEON_DEV_HOST` / `Q_INTERIOR_NEON_PROD_HOST` | 일반 공개 hostname, protected | 환경별 Cilium DNS·5432 egress |
| 기존 `SEALED_SECRETS_CERT` | File | Sealed Secrets 공개 인증서 |
| 기존 `GITLAB_REGISTRY_USERNAME/TOKEN` | masked/protected | 두 이미지 저장소 읽기용 registry secret |

API File 변수 필수 항목은 `SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD`입니다. URL은 JDBC 형식과 SSL 검증을 사용합니다. 시크릿은 기존 sealing job이 암호화해 생성하며 실제 env 파일은 Git에 들어가지 않습니다. Q 인테리어 변수가 없으면 기존 서비스 sealing 동작을 유지합니다.

## 클라이언트 프로젝트 모바일 변수

아래 값은 GitLab의 `q-interior-client` 프로젝트 CI/CD 변수에만 둡니다. dev Firebase 배포 환경(`q-interior-mobile-dev`) 및 protected `main`으로 scope를 제한합니다. signing/Firebase 비밀값을 GitOps 프로젝트나 그룹 공통 변수에 등록하지 않습니다.

| 이름 | 형태 | 사용처 |
| --- | --- | --- |
| `Q_INTERIOR_API_URL` | 공개 설정, protected | 앱 번들에 포함되는 API URL, `/saerom/api/v1` 포함 |
| `Q_INTERIOR_ANDROID_KEYSTORE` | File, protected | Android signing keystore |
| `Q_INTERIOR_ANDROID_STORE_PASSWORD`, `Q_INTERIOR_ANDROID_KEY_ALIAS`, `Q_INTERIOR_ANDROID_KEY_PASSWORD` | masked/protected | Android signing credentials |
| `Q_INTERIOR_FIREBASE_CREDENTIALS` | File, protected | 제한된 App Distribution 권한의 서비스 계정 JSON |
| `Q_INTERIOR_FIREBASE_ANDROID_APP_ID`, `Q_INTERIOR_FIREBASE_IOS_APP_ID` | 일반 설정, protected | Firebase에 등록된 앱 ID |
| `Q_INTERIOR_FIREBASE_GROUPS` | 일반 설정, protected | tester group alias |
| `Q_INTERIOR_IOS_P12`, `Q_INTERIOR_IOS_PROFILE`, `Q_INTERIOR_IOS_EXPORT_OPTIONS` | File, protected | iOS 인증서·provisioning profile·export options |
| `Q_INTERIOR_IOS_P12_PASSWORD` | masked/protected | P12 비밀번호 |
| `Q_INTERIOR_IOS_TEAM_ID` | 일반 설정, protected | Apple Developer 팀 |

## GitLab 설정 선행 조건

1. 그룹에 두 소스 저장소를 생성하고 `main`을 보호합니다. 서명 변수가 있는 모바일 배포 job은 클라이언트 저장소의 보호된 기본 브랜치에서만 실행합니다.
2. 본 저장소 CI include와 downstream 입력 기능을 먼저 병합합니다. 소스 CI는 해당 템플릿이 main에 있어야 시작할 수 있습니다.
3. API·클라이언트 프로젝트의 CI_JOB_TOKEN allowlist에 본 GitOps 프로젝트를 추가합니다. GitOps가 소스를 읽어 고정 SHA를 확인하기 위한 권한입니다.
4. 본 프로젝트가 소스 프로젝트의 웹/API multi-project trigger를 허용하고, 본 프로젝트의 CI_JOB_TOKEN repository push 기능이 켜져 있는지 확인합니다. 기존 sealing push와 동일한 방식입니다. 모바일 job은 이 downstream 경로를 사용하지 않습니다.
5. Registry read token이 새 API·Client 이미지도 읽을 수 있는지 확인합니다. 기존 토큰 값은 코드로 복사하지 않습니다.
6. 런타임 API·Neon·Sealed Secrets 변수를 본 저장소에 설정합니다. 이들은 Kubernetes 런타임 전용이며 앱 서명 변수는 넣지 않습니다.
7. main 이미지 빌드가 성공한 뒤 deploy downstream이 만드는 MR을 검토·병합합니다. prod는 동일 SHA에 대한 `vX.Y.Z` 승격 이미지로 배포합니다.
8. 모바일 배포를 시작하기 전에 클라이언트 프로젝트에 필요한 protected CI/CD 변수와 Firebase 앱·tester group을 설정합니다. iOS는 클라이언트 프로젝트에서 접근 가능한 전용 macOS Runner가 추가로 필요합니다.

원격 변수 생성·권한 변경·production 배포는 이 로컬 작업에서 수행하지 않았습니다. GitLab 저장소가 public인 기존 운영 형태를 새 소스 저장소에 자동 적용하지 않습니다.

## 회원 인증 메일 설정

API env File 변수에 `Q_INTERIOR_SMTP_HOST`, `Q_INTERIOR_SMTP_USERNAME`, `Q_INTERIOR_SMTP_PASSWORD`, `Q_INTERIOR_MAIL_FROM`, `Q_INTERIOR_PUBLIC_WEB_URL`을 추가합니다. 기존 envFrom·SealedSecret 구조를 그대로 사용하며 값을 소스 저장소에 넣지 않습니다.

SMTP는 587 STARTTLS 필수·서버 인증서 hostname 검증을 사용합니다. 메일 서버 DNS 정책에는 GitOps 공개 변수 `Q_INTERIOR_SMTP_DEV_HOST` / `Q_INTERIOR_SMTP_PROD_HOST`를 설정합니다. env File의 SMTP_HOST와 일치해야 합니다. 배포 MR이 정확한 DNS hostname과 587 포트만 허용하며 기본값은 미설정 placeholder입니다.

`Q_INTERIOR_PUBLIC_WEB_URL`은 HTTPS 웹 진입점 전체 주소입니다. 인증 토큰은 URL fragment `#verify=`에 담고, 웹은 읽은 뒤 주소에서 제거합니다. 운영 로그에 토큰·메일 본문·SMTP 비밀번호를 기록하지 않습니다.

`Q_INTERIOR_REGISTRATION_ENABLED`는 기본 false입니다. 현재 동의 문서는 검토용 초안이므로 정식 문서 확정·메일 실수신 테스트·가입/로그인 abuse 방어·발송 실패 모니터링을 완료하기 전에 운영 가입을 활성화하지 않습니다. `local` 프로필과 개발용 메일함은 운영 manifest에 사용하지 않습니다.

## 모바일 Runner 준비

Android job은 클라이언트 CI의 Android SDK 35 이미지·Java 17·Node/Firebase CLI를 사용합니다. 서명 key가 없으면 unsigned 앱을 배포하는 대신 job이 실패합니다. APK artifact나 signing key를 공개 pipeline artifact로 올리지 않습니다.

iOS는 클라이언트 프로젝트에서 사용할 수 있는 `macos`, `q-interior` 태그의 전용 macOS Runner가 필요합니다. Java 17, Xcode, XcodeGen, Node/npm을 준비하고 Firebase CLI는 job이 설치합니다. 보호되지 않은 ref가 이 Runner와 signing 변수를 사용하지 못하게 설정합니다. 임시 keychain·profile은 job 종료 시 제거합니다. 이미 설치된 동일 profile을 덮어쓰지 않습니다. 최초 IPA 실빌드·서명·Firebase 수신 테스트는 해당 Runner에서 별도 확인해야 합니다.

`distribute_android`·`distribute_ios`는 클라이언트 CI의 수동 작업이며 해당 pipeline checkout의 commit을 직접 빌드합니다. 두 job은 현재 dev Firebase 배포만 수행하고 GitOps pipeline을 호출하지 않습니다.

## 검증·미완료

새 YAML·shell·Kustomize 렌더링과 API/웹 빌드는 로컬 검증 대상으로 삼습니다. 실제 GitLab pipeline, registry push, Argo sync, Neon 연결, APK/IPA 서명, Firebase 업로드는 계정·변수·Runner 준비 뒤 확인해야 합니다.

현재 API는 초기 회원·웹 세션·초안 기능만 제공합니다. 이메일 인증·약관 동의·역할 검증·계약·결제 등의 출시 필수 기능이 미완료이므로 운영 ingress와 secret 준비가 곧 서비스 출시를 의미하지 않습니다.

참고: [Firebase CLI tester 배포](https://firebase.google.com/docs/app-distribution/android/distribute-cli), [GitLab downstream pipelines](https://docs.gitlab.com/ci/pipelines/downstream_pipelines/).

# GraphDB 라이선스 발급 및 등록

현재 클러스터는 GraphDB 11.x를 사용하므로 GraphDB Free를 사용하더라도 유효한 라이선스가 필요하다. GraphDB 11.0부터 Free 라이선스도 다운로드 페이지에서 요청해야 하며, 발급본은 요청한 이메일 주소로 전달된다.

## 1. Free 라이선스 발급

1. [GraphDB 공식 제품/다운로드 페이지](https://graphwise.ai/components/graphdb/)에 접속한다.
2. 서버 환경에 맞는 GraphDB 배포 패키지를 선택한다. 이 프로젝트는 Kubernetes에서 실행하므로 플랫폼 독립형 배포 패키지 기준으로 확인한다.
3. 페이지의 `Request GraphDB License` 영역에서 Free 라이선스를 요청한다.
4. 이메일 주소를 입력하고 제출한다.
5. 받은 메일에서 라이선스 원문 또는 `graphdb.license` 파일을 확보한다. 스팸함도 확인한다.

GraphDB Enterprise Edition 평가판 또는 상용 라이선스가 필요한 경우에는 GraphDB 공식 문의처로 요청한다.

## 2. 원문 보존 주의사항

- 메일 본문에서 복사할 경우 라이선스 블록만 복사한다.
- 앞뒤 설명 문구, 따옴표, Markdown 코드펜스, HTML 태그를 포함하지 않는다.
- 라이선스 내부 줄바꿈과 문자를 변경하지 않는다.
- 가능하면 메일 본문 복사보다 공식 다운로드 파일을 우선한다.
- 현재 실행 버전인 GraphDB 11.5.x와 맞는 라이선스를 요청한다. GraphDB 문서상 minor 버전 업그레이드 때도 새 Free 라이선스가 필요할 수 있다.

## 3. 로컬에서 먼저 검증

GraphDB Workbench에서 다음 경로로 등록한다.

`Setup` → `License` → `Set new license` → 파일 업로드 → `Register` → 라이선스 정보 확인

붙여넣기도 가능하지만, 붙여넣은 뒤 반드시 `Register`를 눌러야 한다.

## 4. 현재 Kubernetes/GitLab 구성에 등록

GitLab 프로젝트의 `Settings` → `CI/CD` → `Secure Files` → `Upload File`에서
원본 `.license` 파일을 업로드한다. Secure File 이름은 반드시 다음과 같이 한다.

```text
graphdb.license
```

Base64 변환이나 텍스트 변수 입력은 사용하지 않는다. GitLab Secure Files는
바이너리 파일을 원본 바이트 그대로 보관하며, 파이프라인은 `glab securefile`로
다운로드한 파일을 `kubectl create secret --from-file`에 직접 전달한다.
`ci/secret-files.conf`가 Secure File과 Kubernetes Secret의 매핑을 선언하므로,
새 바이너리 파일을 추가할 때는 해당 manifest에 한 줄을 추가한다.

Secure File은 Git 저장소에 포함되지 않으며, GitOps에는 `kubeseal`이 생성한
암호문만 저장된다.

배포 후에는 다음을 확인한다.

1. `graphdb-license` Secret이 생성되는지 확인
2. GraphDB 컨테이너의 `/opt/graphdb/home/conf/license/graphdb.license`에 마운트되는지 확인
3. GraphDB 라이선스 검증 오류가 사라지는지 확인
4. GraphDB readiness와 온톨로지 API readiness가 정상으로 바뀌는지 확인
5. Argo CD에서 온톨로지 API가 `Synced / Healthy`인지 확인

## 공식 자료

- [GraphDB 제품 및 다운로드 페이지](https://graphwise.ai/components/graphdb/)
- [GraphDB 11.1 라이선싱](https://graphdb.ontotext.com/documentation/11.1/licensing.html)
- [GraphDB 11.0 라이선스 설정](https://graphdb.ontotext.com/documentation/11.0/set-up-your-license.html)

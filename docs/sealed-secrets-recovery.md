# Sealed Secrets 키 백업 및 복구 런북

Sealed Secrets Controller는 복호화에 필요한 Private Key를 Kubernetes Secret으로
보관합니다. Controller key를 잃은 뒤에는 Git에 저장된 암호화 파일만으로 기존
Secret 값을 복구할 수 없습니다.

이 문서는 **Private Key의 외부 백업과 복구**만 다룹니다. 공개 인증서 등록은
[`sealed-secrets-certificate.md`](sealed-secrets-certificate.md)를 따릅니다.

> 이 문서의 명령은 예시입니다. 꺾쇠 괄호 값을 그대로 실행하지 말고, 승인된
> kubeconfig·context·암호화 백업 경로로 바꾸십시오. Private Key 내용, kubeconfig,
> Secret YAML을 로그·GitLab 변수·artifact·채팅에 출력하지 마십시오.

## 안전 조건

- 백업은 Git 저장소 밖의 **기존 암호화·접근통제 절대 경로**에 보관합니다.
  저장소의 `.gitignore`만으로 Private Key를 보호할 수 없습니다.
- 백업과 복구를 시작하기 전에 운영자가 대상 클러스터, provider/account,
  API endpoint, Kubernetes context를 서로 대조합니다. `cluster-info`는 연결
  가능성만 증명하며 클러스터 신원을 증명하지 않습니다.
- `sealedsecrets.bitnami.com/sealed-secrets-key` label이 붙은 **모든** Secret을
  보존합니다. Controller가 주기적으로 키를 교체하면 여러 개의 오래된 키가
  필요할 수 있습니다. `sealed-secrets-key`라는 단일 이름만 가정하거나 오래된
  키를 임의로 삭제하지 않습니다.
- 복구 중에는 workload 및 SealedSecret Application의 Argo CD 동기화를 일시
  중지하거나 승인된 방식으로 hold합니다. 키 복구와 Controller 검증이 끝난 뒤에
  workload 동기화를 재개합니다.
- Private Key 백업을 GitLab CI/CD 변수, 일반 artifact, 공개 저장소, 일반 파일
  공유에 올리지 않습니다.

## 공통 대상 설정 및 사전 확인

아래 값은 실제 운영 값으로 교체합니다. `$BackupDirectory`는 이미 만들어진
암호화 저장소여야 하며, 이 런북이 평문 백업 디렉터리를 자동으로 만들도록 하지
않습니다.

```powershell
$KubeConfigFile = 'C:\secure\kubeconfigs\<target>.config'
$KubeContext = '<exact-context>'
$Namespace = 'sealed-secrets'
$ControllerDeployment = 'sealed-secrets-controller'
$BackupDirectory = 'D:\encrypted-backups\sealed-secrets'

if (-not [IO.Path]::IsPathFullyQualified($KubeConfigFile)) {
  throw 'Kubeconfig path must be absolute'
}
if (-not [IO.Path]::IsPathFullyQualified($BackupDirectory)) {
  throw 'Backup directory must be an absolute path'
}
if (-not (Test-Path -LiteralPath $KubeConfigFile -PathType Leaf)) {
  throw 'Kubeconfig file does not exist'
}
if (-not (Test-Path -LiteralPath $BackupDirectory -PathType Container)) {
  throw 'Create and verify an encrypted backup directory before continuing'
}

$currentContext = kubectl --kubeconfig $KubeConfigFile --context $KubeContext config current-context
if ($LASTEXITCODE -ne 0 -or $currentContext.Trim() -ne $KubeContext) {
  throw 'The selected kubeconfig/context could not be verified'
}

kubectl --kubeconfig $KubeConfigFile --context $KubeContext cluster-info
if ($LASTEXITCODE -ne 0) { throw 'The selected cluster is not reachable' }

kubectl --kubeconfig $KubeConfigFile --context $KubeContext -n $Namespace get namespace $Namespace
if ($LASTEXITCODE -ne 0) { throw 'The Sealed Secrets namespace is not available' }
```

`kubectl` 명령을 다른 셸에서 이어서 실행할 때는 `$KubeConfigFile`과
`$KubeContext`를 다시 설정하고, 모든 명령에 두 옵션을 반복합니다. Ambient
`KUBECONFIG` 또는 현재 context에 의존하지 않습니다.

## 1. 실행 중인 Controller의 키 백업

### 실행 전 확인

1. 운영 기록과 대상 cluster identity를 대조합니다.
2. Controller가 의도한 namespace에서 실행 중인지 확인합니다.
3. 암호화 백업 경로가 외부·절대 경로이고 접근통제 및 암호화 상태인지 확인합니다.
4. 백업 명령이 실패해도 최종 백업 파일을 만들지 않도록 고유한 staging 파일을
   백업 디렉터리 안에 만듭니다. 같은 디렉터리 안에서 이동해야 최종 교체가
   원자적으로 수행될 수 있습니다.

```powershell
kubectl --kubeconfig $KubeConfigFile --context $KubeContext `
  -n $Namespace get deployment $ControllerDeployment
if ($LASTEXITCODE -ne 0) { throw 'Controller Deployment was not found' }

kubectl --kubeconfig $KubeConfigFile --context $KubeContext `
  -n $Namespace rollout status deployment/$ControllerDeployment --timeout=120s
if ($LASTEXITCODE -ne 0) { throw 'Controller Deployment is not ready' }

kubectl --kubeconfig $KubeConfigFile --context $KubeContext `
  -n $Namespace get pods
if ($LASTEXITCODE -ne 0) { throw 'Controller Pods could not be inspected' }

$BackupName = 'sealed-secrets-keys-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.yaml'
$BackupPath = Join-Path $BackupDirectory $BackupName
$StagePath = Join-Path $BackupDirectory ('.' + $BackupName + '.' + [guid]::NewGuid().ToString('N') + '.tmp')

try {
  $BackupLines = @(kubectl --kubeconfig $KubeConfigFile --context $KubeContext `
    -n $Namespace get secret `
    --selector 'sealedsecrets.bitnami.com/sealed-secrets-key' `
    --output yaml)
  $KubectlExitCode = $LASTEXITCODE
  if ($KubectlExitCode -ne 0) { throw 'kubectl failed while exporting the key Secrets' }
  $BackupText = $BackupLines -join [Environment]::NewLine
  if ([string]::IsNullOrWhiteSpace($BackupText)) {
    throw 'The key backup is empty; no labeled key Secret was exported'
  }
  Set-Content -LiteralPath $StagePath -Value $BackupText -Encoding utf8

  if (-not (Test-Path -LiteralPath $StagePath -PathType Leaf)) {
    throw 'The staging backup file was not created'
  }
  $BackupText = Get-Content -LiteralPath $StagePath -Raw
  if ([string]::IsNullOrWhiteSpace($BackupText)) {
    throw 'The key backup is empty; no labeled key Secret was exported'
  }
  if ($BackupText -notmatch '(?m)^items:\s*$' -or
      $BackupText -notmatch 'sealedsecrets\.bitnami\.com/sealed-secrets-key') {
    throw 'The export does not look like a labeled multi-Secret backup'
  }

  Move-Item -LiteralPath $StagePath -Destination $BackupPath
  Write-Host "Key backup moved to the protected external destination: $BackupPath"
} finally {
  Remove-Item -LiteralPath $StagePath -Force -ErrorAction SilentlyContinue
}
```

`kubectl`의 YAML 출력이나 백업 파일 내용을 화면에 출력하지 않습니다. `items:`가
없거나 label이 없거나 결과가 비어 있으면 백업을 최종 경로로 이동하지 않습니다.
백업이 성공한 뒤 운영자가 암호화 저장소의 복호화·접근 권한과 파일 무결성을 별도
절차로 확인합니다. Key rotation 뒤에는 같은 절차를 다시 실행하여 새로 생성된
labelled Secret도 보존합니다. 기존 백업을 덮어쓰지 말고 시점별 백업을 유지합니다.

## 2. Cluster 재구성: Controller 시작 전 복구

이 경로는 새 cluster에서 workload SealedSecret을 동기화하기 **전**에 사용합니다.

### 실행 전 확인

- Argo CD에서 workload 및 SealedSecret 동기화를 hold하고, 복구 대상 cluster가
  공통 설정의 `$KubeConfigFile`/`$KubeContext`와 일치하는지 다시 확인합니다.
- 승인된 암호화 백업에서 복구할 파일을 선택합니다. 파일을 열어 Private Key를
  출력하지 말고, 파일 경로와 생성 시점만 운영 기록으로 확인합니다.
- Sealed Secrets namespace가 존재하고, workload Application은 아직 동기화하지
  않았는지 확인합니다.

```powershell
$BackupPath = 'D:\encrypted-backups\sealed-secrets\<verified-backup>.yaml'
if (-not [IO.Path]::IsPathFullyQualified($BackupPath) -or
    -not (Test-Path -LiteralPath $BackupPath -PathType Leaf)) {
  throw 'Use a verified external backup file'
}

kubectl --kubeconfig $KubeConfigFile --context $KubeContext `
  -n $Namespace get namespace $Namespace
if ($LASTEXITCODE -ne 0) { throw 'Create the namespace through the approved controller deployment path first' }

kubectl --kubeconfig $KubeConfigFile --context $KubeContext `
  -n $Namespace apply --filename $BackupPath
if ($LASTEXITCODE -ne 0) { throw 'Key Secret restore failed' }

kubectl --kubeconfig $KubeConfigFile --context $KubeContext `
  -n $Namespace get secret `
  --selector 'sealedsecrets.bitnami.com/sealed-secrets-key' `
  --output custom-columns='NAME:.metadata.name,CREATED:.metadata.creationTimestamp'
if ($LASTEXITCODE -ne 0) { throw 'Restored key Secrets could not be verified' }
```

namespace가 없다면 Controller Deployment가 시작되지 않은 상태에서 승인된 방법으로
namespace만 먼저 생성합니다. 현재 `sealed-secrets` Application은 `CreateNamespace=true`와
Helm Controller Deployment를 하나의 Application으로 관리하므로, Application 전체를
동기화하면 Controller가 먼저 시작되어 새 key를 만들 수 있습니다. 그러므로 namespace
생성만을 위해 Application 전체를 무심코 동기화하지 말고, 운영자가 승인한 namespace
생성 또는 Controller 배포 hold 절차를 사용합니다. namespace가 준비되면 위의 restore를
실행하고, 복구 확인 뒤에만 Sealed Secrets Application을 동기화/재개하여 Controller를
시작합니다.

```powershell
kubectl --kubeconfig $KubeConfigFile --context $KubeContext `
  -n $Namespace rollout status deployment/$ControllerDeployment --timeout=120s
if ($LASTEXITCODE -ne 0) { throw 'Controller did not become ready after key restore' }

kubectl --kubeconfig $KubeConfigFile --context $KubeContext `
  -n $Namespace get secret `
  --selector 'sealedsecrets.bitnami.com/sealed-secrets-key' `
  --output custom-columns='NAME:.metadata.name,CREATED:.metadata.creationTimestamp'
if ($LASTEXITCODE -ne 0) { throw 'Restored key set is not visible' }
```

Controller rollout과 key set을 확인한 뒤에만 workload 및 SealedSecret Application의
Argo CD 동기화를 재개합니다. 이후 기존 SealedSecret이 생성한 Kubernetes Secret과
애플리케이션 상태를 별도 검증합니다.

## 3. 이미 새 key를 만든 Controller의 late-start 복구

새 Controller가 이미 시작되어 새 sealing key를 만든 경우에도 기존 generated key를
먼저 삭제하지 않습니다. 기존 key와 rotated key를 모두 보존한 상태에서 승인된
백업의 전체 labeled Secret set을 적용합니다.

```powershell
kubectl --kubeconfig $KubeConfigFile --context $KubeContext `
  -n $Namespace apply --filename $BackupPath
if ($LASTEXITCODE -ne 0) { throw 'Late-start key restore failed' }

kubectl --kubeconfig $KubeConfigFile --context $KubeContext `
  -n $Namespace rollout restart deployment/$ControllerDeployment
if ($LASTEXITCODE -ne 0) { throw 'Controller restart failed' }

kubectl --kubeconfig $KubeConfigFile --context $KubeContext `
  -n $Namespace rollout status deployment/$ControllerDeployment --timeout=120s
if ($LASTEXITCODE -ne 0) { throw 'Controller rollout did not complete' }

kubectl --kubeconfig $KubeConfigFile --context $KubeContext `
  -n $Namespace get secret `
  --selector 'sealedsecrets.bitnami.com/sealed-secrets-key' `
  --output custom-columns='NAME:.metadata.name,CREATED:.metadata.creationTimestamp'
if ($LASTEXITCODE -ne 0) { throw 'The complete labeled key set could not be verified' }
```

Controller 로그에 Private Key나 Secret 값을 출력하지 않는 방식으로 복호화 오류와
기존 SealedSecret 처리 상태를 확인합니다. 키가 여러 개 보이는 것은 정상적인
rotation 상태일 수 있으므로, 원인 확인 없이 오래된 Secret을 삭제하지 않습니다.
복구 및 rollout 검증이 끝난 뒤에만 workload 동기화를 재개합니다.

## 키 백업이 없거나 복호화가 실패하는 경우

- Private Key가 없으면 기존 ciphertext를 공개 인증서만으로 되돌릴 수 없습니다.
- Controller와 이전 key가 모두 남아 있는 경우에만 해당 Controller가 지원하는
  re-encrypt 절차를 검토합니다. 무조건 `kubeseal --re-encrypt`가 가능한 것은
  아닙니다.
- 이전 key를 잃은 경우 원래 평문 Secret 값을 안전한 입력 경로로 다시 준비하고,
  현재 Controller 공개 인증서로 SealedSecret을 재생성한 뒤 기존 자격 증명을
  폐기·교체합니다.
- Private Key를 GitLab 변수, CI artifact, 로그, Git commit 또는 채팅에 넣지
  않습니다.

## 관련 문서

- [`sealed-secrets-certificate.md`](sealed-secrets-certificate.md) — 공개 인증서 취득
- [`secret-variables.md`](secret-variables.md) — GitLab File 변수 형식
- [`next-steps.md`](next-steps.md) — 복구 훈련 및 보류 작업

# Windows 入口：把任务名转成 Git Bash 里的脚本调用，省得记路径。
#   powershell -File scripts\ohos.ps1 doctor
#   powershell -File scripts\ohos.ps1 pipeline
#   powershell -File scripts\ohos.ps1 deploy -Target 192.168.1.23:5555
#
# 只依赖 Git Bash（bash.exe）。所有实际逻辑都在同名 .sh 里，CI 上直接跑 sh 即可。
[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [ValidateSet('doctor', 'build', 'sign', 'deploy', 'pipeline', 'tcp', 'photos',
               'sdk', 'hvigor', 'material', 'summary', 'check', 'shell')]
  [string]$Task = 'doctor',
  [string]$Target,
  [string]$Release
)

$ErrorActionPreference = 'Stop'

$bash = Get-Command 'C:\Program Files\Git\bin\bash.exe' -ErrorAction SilentlyContinue
if (-not $bash) { $bash = Get-Command 'C:\Program Files\Git\usr\bin\bash.exe' -ErrorAction SilentlyContinue }
if (-not $bash) { $bash = Get-Command 'bash' -ErrorAction SilentlyContinue }
if (-not $bash) { Write-Host '找不到 bash.exe（装 Git for Windows），直接用 Git Bash 跑 scripts/*.sh。' -ForegroundColor Red; exit 1 }

$root = Split-Path -Parent $PSScriptRoot
$map = @{
  doctor   = 'scripts/doctor.sh'
  build    = 'scripts/build.sh'
  sign     = 'scripts/sign.sh'
  deploy   = 'scripts/deploy.sh'
  pipeline = 'scripts/pipeline.sh'
  tcp      = 'scripts/tcp-mode.sh'
  photos   = 'scripts/push-photos.sh'
  sdk      = 'scripts/get-ohos-sdk.sh'
  hvigor   = 'scripts/install-hvigor.sh'
  material = 'scripts/make-signing-material.sh'
  summary  = 'scripts/ci-summary.sh'
  check    = 'tools/validate-project.js'
  shell    = ''
}

$script = $map[$Task]
if ($Task -eq 'shell') { Write-Host "进入 Git Bash，工程根：$root" -ForegroundColor Cyan; & $bash.Source --login; exit $LASTEXITCODE }

# 环境变量只在这个进程里设，别写进 shell 配置
if ($Target) { $env:OHOS_TARGET = $Target }
if ($Release) { $env:OHOS_BUILD_MODE = 'release' }

Push-Location $root
try {
  if ($Task -eq 'check') {
    & node $script
  } else {
    Write-Host "==> bash $script" -ForegroundColor Cyan
    & $bash.Source $script
  }
  $code = $LASTEXITCODE
} finally { Pop-Location }

if ($code -ne 0) { Write-Host "退出码 $code" -ForegroundColor Yellow }
exit $code

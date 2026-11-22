$ErrorActionPreference = 'Stop'
$jdk = if ($env:OHOS_JDK) { $env:OHOS_JDK }
       elseif ($env:OHOS_TOOLS) { Join-Path $env:OHOS_TOOLS 'java\jdk-17' }
       elseif ($env:DEVECO_HOME) { Join-Path $env:DEVECO_HOME 'jbr' }
       else { throw '未找到 JDK：请设置 OHOS_JDK 或 OHOS_TOOLS/DEVECO_HOME' }
if (-not (Test-Path (Join-Path $jdk 'bin\java.exe'))) { throw "JDK 路径无效：$jdk" }
[Environment]::SetEnvironmentVariable('JAVA_HOME', $jdk, 'User')
$p = [Environment]::GetEnvironmentVariable('Path', 'User')
if ([string]::IsNullOrEmpty($p)) { $p = '' }
if ($p -notlike '*jdk-17\bin*') {
  if ($p.Length -eq 0) { $np = "$jdk\bin" } else { $np = "$jdk\bin;$p" }
  [Environment]::SetEnvironmentVariable('Path', $np, 'User')
}
Write-Output ("JAVA_HOME(User) = " + [Environment]::GetEnvironmentVariable('JAVA_HOME', 'User'))
Write-Output ("Path(User) head = " + ([Environment]::GetEnvironmentVariable('Path', 'User')).Substring(0, 80))

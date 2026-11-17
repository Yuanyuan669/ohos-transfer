$ErrorActionPreference = 'Stop'
$jdk = 'D:\ohos-tools\java\jdk-17'
[Environment]::SetEnvironmentVariable('JAVA_HOME', $jdk, 'User')
$p = [Environment]::GetEnvironmentVariable('Path', 'User')
if ([string]::IsNullOrEmpty($p)) { $p = '' }
if ($p -notlike '*jdk-17\bin*') {
  if ($p.Length -eq 0) { $np = "$jdk\bin" } else { $np = "$jdk\bin;$p" }
  [Environment]::SetEnvironmentVariable('Path', $np, 'User')
}
Write-Output ("JAVA_HOME(User) = " + [Environment]::GetEnvironmentVariable('JAVA_HOME', 'User'))
Write-Output ("Path(User) head = " + ([Environment]::GetEnvironmentVariable('Path', 'User')).Substring(0, 80))

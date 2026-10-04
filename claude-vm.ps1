# Claude Code na VM Windows Server 2019 (Skymail W-39869-DB-01)
# Faz o login com a conta Google DENTRO da VM (Chrome) e deixa o Claude abrindo sozinho ao entrar na VM.
# Uso (PowerShell como Administrador), uma linha so:
#   [Net.ServicePointManager]::SecurityProtocol='Tls12'; irm https://raw.githubusercontent.com/marcosguibs-debug/vm-setup/main/claude-vm.ps1 | iex
function Start-ClaudeVmSetup {
  $ErrorActionPreference = 'Stop'
  $H = $env:USERPROFILE
  $BIN = Join-Path $H '.local\bin'
  $CLAUDE = Join-Path $BIN 'claude.exe'
  if (-not (Test-Path $CLAUDE)) {
    $c = Get-Command claude.exe -ErrorAction SilentlyContinue
    if ($c) { $CLAUDE = $c.Source } else {
      Write-Host '== Claude Code nao encontrado: instalando' -ForegroundColor Cyan
      Invoke-RestMethod https://claude.ai/install.ps1 | Invoke-Expression
      if (-not (Test-Path $CLAUDE)) { Write-Host 'ERRO: instalacao do Claude falhou. Me mande esta tela.' -ForegroundColor Red; return }
    }
  }
  Write-Host "Claude: $CLAUDE"
  $PASTA = $H
  foreach ($p in @('C:\dashml', (Join-Path $H 'Downloads\aton-bridge'))) { if (Test-Path $p) { $PASTA = $p; break } }
  Write-Host "Pasta de trabalho: $PASTA"

  Write-Host '== [1/6] limpar tentativa anterior (token)' -ForegroundColor Cyan
  [Environment]::SetEnvironmentVariable('CLAUDE_CODE_OAUTH_TOKEN', $null, 'User')
  Remove-Item Env:\CLAUDE_CODE_OAUTH_TOKEN -ErrorAction SilentlyContinue
  Remove-Item Env:\ANTHROPIC_API_KEY -ErrorAction SilentlyContinue

  Write-Host '== [2/6] PATH' -ForegroundColor Cyan
  $up = [Environment]::GetEnvironmentVariable('Path', 'User'); if (-not $up) { $up = '' }
  if (($up -split ';') -notcontains $BIN) { [Environment]::SetEnvironmentVariable('Path', ($BIN + ';' + $up).TrimEnd(';'), 'User') }
  $env:Path = $BIN + ';' + $env:Path

  Write-Host '== [3/6] navegador moderno (o Internet Explorer do Server 2019 nao faz login Google)' -ForegroundColor Cyan
  $nav = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
           "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
           "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $nav) {
    Write-Host '  instalando Google Chrome (1-3 min)...'
    $msi = Join-Path $env:TEMP 'chrome.msi'
    (New-Object Net.WebClient).DownloadFile('https://dl.google.com/chrome/install/googlechromestandaloneenterprise64.msi', $msi)
    Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait
    $nav = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
    if (-not (Test-Path $nav)) { Write-Host 'ERRO: Chrome nao instalou. Me mande esta tela.' -ForegroundColor Red; return }
  }
  Write-Host "  navegador: $nav"

  Write-Host '== [4/6] login com a conta Google' -ForegroundColor Cyan
  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = $CLAUDE; $psi.Arguments = 'auth login --claudeai'
  $psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true
  $psi.WorkingDirectory = $H
  $proc = [Diagnostics.Process]::Start($psi)
  $url = $null
  $limite = (Get-Date).AddSeconds(60)
  while (-not $url -and (Get-Date) -lt $limite -and -not $proc.HasExited) {
    $linha = $proc.StandardOutput.ReadLine()
    if ($linha -match '(https://\S+oauth/authorize\S+)') { $url = $Matches[1] }
  }
  if (-not $url -and -not $proc.HasExited) { Write-Host 'ERRO: o Claude nao mostrou o link de login. Me mande esta tela.' -ForegroundColor Red; $proc.Kill(); return }
  if ($url) {
    Start-Process $nav -ArgumentList "`"$url`""
    Write-Host ''
    Write-Host '  >>> Abriu o Chrome. Entre com a conta Google e autorize.' -ForegroundColor Yellow
    Write-Host '  >>> Vai aparecer um CODIGO: clique em Copiar, volte aqui, clique com o BOTAO DIREITO nesta janela (cola) e tecle Enter.' -ForegroundColor Yellow
    Write-Host '  >>> Se em vez do codigo aparecer "Tudo pronto", so tecle Enter aqui.' -ForegroundColor Yellow
    Write-Host '  >>> Se abrir tambem o Internet Explorer, feche ele.' -ForegroundColor Yellow
    $codigo = (Read-Host '  Codigo') -replace '\s', ''
    if (-not $proc.HasExited) {
      if ($codigo) { $proc.StandardInput.WriteLine($codigo) }
      $proc.StandardInput.Close()
    }
  }
  $ErrorActionPreference = 'Continue'
  $resto = $proc.StandardOutput.ReadToEnd()
  [void]$proc.WaitForExit(60000)
  if ($resto) { Write-Host ($resto -replace 'https://\S+', '[link]') }
  $st = (& $CLAUDE auth status --json 2>&1 | Out-String)
  if ($st -notmatch '"loggedIn":\s*true') { Write-Host "ERRO: login nao concluiu. Status: $st" -ForegroundColor Red; Write-Host 'Rode a linha de novo; se repetir, me mande esta tela.'; return }
  Write-Host '  LOGIN OK' -ForegroundColor Green

  Write-Host '== [5/6] pular boas-vindas e confianca da pasta' -ForegroundColor Cyan
  $cj = Join-Path $H '.claude.json'
  $d = $null
  try {
    if (Test-Path $cj) { Copy-Item $cj "$cj.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"; $d = Get-Content $cj -Raw -Encoding UTF8 | ConvertFrom-Json } else { $d = New-Object PSObject }
  } catch { Write-Host "  aviso: nao li $cj; o Claude pode perguntar tema/confianca uma vez." -ForegroundColor Yellow }
  if ($d) {
    $d | Add-Member -NotePropertyName hasCompletedOnboarding -NotePropertyValue $true -Force
    if (-not $d.PSObject.Properties['projects']) { $d | Add-Member -NotePropertyName projects -NotePropertyValue (New-Object PSObject) }
    foreach ($k in @($PASTA, ($PASTA -replace '\\', '/'), $H, ($H -replace '\\', '/'))) {
      if (-not $d.projects.PSObject.Properties[$k]) { $d.projects | Add-Member -NotePropertyName $k -NotePropertyValue (New-Object PSObject) }
      $d.projects.$k | Add-Member -NotePropertyName hasTrustDialogAccepted -NotePropertyValue $true -Force
    }
    [IO.File]::WriteAllText($cj, ($d | ConvertTo-Json -Depth 100), (New-Object Text.UTF8Encoding $false))
  }

  Write-Host '== [6/6] abrir sozinho ao entrar na VM' -ForegroundColor Cyan
  $DIR = Join-Path $H '.claude-vm'; New-Item -ItemType Directory -Force -Path $DIR | Out-Null
  $LOOP = Join-Path $DIR 'claude-loop.ps1'
@"
`$Host.UI.RawUI.WindowTitle = 'Claude Code'
Remove-Item Env:\CLAUDE_CODE_OAUTH_TOKEN -ErrorAction SilentlyContinue
`$env:Path = '$BIN;' + `$env:Path
Set-Location '$PASTA'
while (`$true) {
  & '$CLAUDE'
  Write-Host ''
  Write-Host 'Claude fechou. Qualquer tecla = ficar no PowerShell. Sem nada, reabre em 10s.'
  `$fica = `$false
  for (`$i = 0; `$i -lt 100; `$i++) { if ([Console]::KeyAvailable) { [void][Console]::ReadKey(`$true); `$fica = `$true; break }; Start-Sleep -Milliseconds 100 }
  if (`$fica) { break }
}
"@ | Set-Content -Path $LOOP -Encoding UTF8
  $TASK = 'Claude Code ao entrar'
  $user = "$env:USERDOMAIN\$env:USERNAME"
  $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$LOOP`"" -WorkingDirectory $PASTA
  $trg = New-ScheduledTaskTrigger -AtLogOn -User $user
  $pri = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
  $set = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
  Register-ScheduledTask -TaskName $TASK -Action $act -Trigger $trg -Principal $pri -Settings $set -Force | Out-Null

  Write-Host ''
  Write-Host '======== PROVA ========' -ForegroundColor Cyan
  $ErrorActionPreference = 'Continue'
  Push-Location $H
  $r = (& $CLAUDE -p 'Responda somente a palavra OK' 2>&1 | Out-String)
  Pop-Location
  $tk = Get-ScheduledTask -TaskName $TASK
  Write-Host ("login:            " + (& $CLAUDE auth status --text 2>&1 | Out-String).Trim())
  Write-Host ("teste do Claude:  " + $r.Trim())
  Write-Host ("abrir ao entrar:  tarefa '" + $tk.TaskName + "' estado " + $tk.State)
  if ($r -cmatch '(?m)^\s*OK\.?\s*$') {
    Start-ScheduledTask -TaskName $TASK
    Write-Host 'TUDO OK. Abri a janela "Claude Code" agora; a partir de hoje ela abre sozinha sempre que voce entrar na VM.' -ForegroundColor Green
  } else {
    Write-Host 'ATENCAO: o teste nao respondeu OK. Me mande esta tela.' -ForegroundColor Yellow
  }
}
Start-ClaudeVmSetup
# FIM DO SCRIPT

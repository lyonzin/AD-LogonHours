<#
.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.
|   ____       _        _    ____  _                            _   _                          |
|  / ___|  ___| |_     / \  |  _ \| |    ___   __ _  ___  _ _ | | | | ___  _   _ _ __ ___     |
|  \___ \ / _ \ __|   / _ \ | | | | |   / _ \ / _` |/ _ \| ' \| |_| |/ _ \| | | | '__/ __|    |
|   ___) |  __/ |_   / ___ \| |_| | |__| (_) | (_| | (_) | | ||  _  | (_) | |_| | |  \__ \    |
|  |____/ \___|\__| /_/   \_\____/|_____\___/ \__, |\___/|_| ||_| |_|\___/ \__,_|_|  |___/    |
|                                              |___/                                           |
.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.
|  Restricao de Horario de Logon via Active Directory                                          |
.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.
|  Criado por:          Ailton Rocha (Lyon.)                                                   |
|  GitHub:              github.com/lyonzin                                                     |
|  Data de Criacao:     2026-01-27                                                             |
|  Ultima Modificacao:  2026-01-27                                                             |
|  Versao:              1.0.0                                                                  |
.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.
|                                                                                              |
|  DESCRICAO:                                                                                  |
|  Configura o atributo logonHours no Active Directory para restringir                         |
|  os horarios em que usuarios podem autenticar no dominio.                                    |
|                                                                                              |
|  COMO FUNCIONA:                                                                              |
|  - O AD usa um byte array de 21 bytes (168 bits = 7 dias x 24 horas)                        |
|  - Cada bit representa 1 hora da semana (1 = pode logar, 0 = bloqueado)                     |
|  - O AD armazena tudo em UTC, o script converte BRT -> UTC automaticamente                   |
|  - Gera backup automatico do estado anterior de cada usuario em CSV                          |
|                                                                                              |
|  VARIAVEIS PRINCIPAIS:                                                                       |
|  - $HorarioPermitidoDe  = Hora que o usuario PODE comecar a logar (BRT)                     |
|  - $HorarioPermitidoAte = Hora que o usuario NAO PODE mais logar (BRT)                      |
|  - Se De > Ate, o script detecta range noturno (cruza meia-noite)                            |
|                                                                                              |
|  EXEMPLO PRODUCAO (bloquear 23:00 ate 03:00 BRT):                                           |
|    $HorarioPermitidoDe  = 3   --> pode logar a partir das 03:00                              |
|    $HorarioPermitidoAte = 23  --> nao pode mais a partir das 23:00                           |
|                                                                                              |
|  NOTA IMPORTANTE:                                                                            |
|  O AD trabalha em blocos de 1 hora (nao existe granularidade de minutos).                    |
|  O bloqueio impede NOVO logon, mas NAO desconecta quem ja esta logado.                       |
|  Para forcar logoff, habilitar na GPO:                                                       |
|  "Network Security: Force logoff when logon hours expire"                                    |
|                                                                                              |
.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.

.SYNOPSIS
    Restringe horarios de logon no AD para lista de matriculas.

.EXAMPLE
    .\Set-ADLogonHours.ps1
#>

[CmdletBinding(SupportsShouldProcess)]
param()

# .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.
# |  PARAMETROS FIXOS - Altere aqui conforme necessidade              |
# .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.
# |                                                                   |
# |  BLOQUEIO desejado: 23:00 ate 03:00 (BRT)                        |
# |  Ou seja, o usuario SO PODE logar entre 03:00 e 23:00            |
# |                                                                   |
# .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.
$UserList             = ".\usuarios.txt"  # Altere para o caminho da sua lista
$HorarioPermitidoDe  = 3     # Usuario PODE logar A PARTIR deste horario (BRT)
$HorarioPermitidoAte = 23    # Usuario NAO PODE mais logar A PARTIR deste horario (BRT)
$DiasAplicados       = @('Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday')
$UTCOffset           = -3    # BRT = UTC-3
$LogPath             = ".\LogonHours_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
# .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.


# ════════════════════════════════════════════════════════════════════
#  PRE-REQUISITOS
# ────────────────────────────────────────────────────────────────────
#  Verifica ANTES de executar qualquer coisa:
#    1. PowerShell rodando como Administrador
#    2. Modulo ActiveDirectory disponivel (oferece instalar se ausente)
#    3. Maquina com acesso a um Domain Controller
#    4. Arquivo de usuarios existe no caminho informado
#
#  Se qualquer pre-requisito falhar, o script PARA com mensagem clara.
# ════════════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "  .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~." -ForegroundColor DarkYellow
Write-Host "  |  Verificando pre-requisitos...                           |" -ForegroundColor DarkYellow
Write-Host "  .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~." -ForegroundColor DarkYellow
Write-Host ""

$preReqOk = $true

# ── 1. Verificar se esta rodando como Administrador ──
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    Write-Host "  [OK] PowerShell rodando como Administrador" -ForegroundColor Green
} else {
    Write-Host "  [FALHA] PowerShell NAO esta rodando como Administrador" -ForegroundColor Red
    Write-Host "          Execute o PowerShell com 'Executar como Administrador'" -ForegroundColor Red
    $preReqOk = $false
}

# ── 2. Verificar modulo ActiveDirectory ──
$adModule = Get-Module -ListAvailable -Name ActiveDirectory -ErrorAction SilentlyContinue

if ($adModule) {
    Write-Host "  [OK] Modulo ActiveDirectory encontrado (v$($adModule.Version))" -ForegroundColor Green
    Import-Module ActiveDirectory -ErrorAction SilentlyContinue
} else {
    Write-Host "  [FALHA] Modulo ActiveDirectory NAO encontrado" -ForegroundColor Red
    Write-Host ""
    Write-Host "  O modulo pode ser instalado de duas formas:" -ForegroundColor Yellow
    Write-Host "    - Windows Server: Install-WindowsFeature RSAT-AD-PowerShell" -ForegroundColor Yellow
    Write-Host "    - Windows 10/11: Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0" -ForegroundColor Yellow
    Write-Host ""

    $resposta = Read-Host "  Deseja instalar agora? (S/N)"

    if ($resposta -match '^[Ss]$') {
        Write-Host ""
        Write-Host "  Instalando modulo ActiveDirectory..." -ForegroundColor Cyan

        $isServer = (Get-CimInstance Win32_OperatingSystem).ProductType -ne 1

        try {
            if ($isServer) {
                # Windows Server: usa Install-WindowsFeature
                Write-Host "  Detectado: Windows Server" -ForegroundColor Cyan
                Install-WindowsFeature RSAT-AD-PowerShell -IncludeAllSubFeature -ErrorAction Stop | Out-Null
            } else {
                # Windows Client (10/11): usa Add-WindowsCapability
                Write-Host "  Detectado: Windows Client (10/11)" -ForegroundColor Cyan
                Add-WindowsCapability -Online -Name "Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0" -ErrorAction Stop | Out-Null
            }

            # Verificar se instalou com sucesso
            $adModuleCheck = Get-Module -ListAvailable -Name ActiveDirectory -ErrorAction SilentlyContinue
            if ($adModuleCheck) {
                Import-Module ActiveDirectory -ErrorAction Stop
                Write-Host "  [OK] Modulo ActiveDirectory instalado com sucesso!" -ForegroundColor Green
            } else {
                Write-Host "  [FALHA] Instalacao concluiu mas modulo nao foi encontrado." -ForegroundColor Red
                Write-Host "          Reinicie o PowerShell e tente novamente." -ForegroundColor Red
                $preReqOk = $false
            }
        }
        catch {
            Write-Host "  [FALHA] Erro ao instalar: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "          Tente instalar manualmente e execute o script novamente." -ForegroundColor Red
            $preReqOk = $false
        }
    } else {
        Write-Host "  Instalacao cancelada pelo usuario. Script encerrado." -ForegroundColor Yellow
        exit 0
    }
}

# ── 3. Verificar conectividade com Domain Controller ──
try {
    $dc = Get-ADDomainController -Discover -ErrorAction Stop
    Write-Host "  [OK] Domain Controller acessivel: $($dc.HostName)" -ForegroundColor Green
}
catch {
    Write-Host "  [FALHA] Nao foi possivel contactar um Domain Controller" -ForegroundColor Red
    Write-Host "          Verifique se a maquina esta no dominio e tem rede com o DC" -ForegroundColor Red
    $preReqOk = $false
}

# ── 4. Verificar se arquivo de usuarios existe ──
if (Test-Path $UserList) {
    $lineCount = (Get-Content $UserList | Where-Object { $_.Trim() -ne '' -and $_ -notmatch '^\s*#' }).Count
    Write-Host "  [OK] Arquivo de usuarios encontrado ($lineCount matriculas)" -ForegroundColor Green
} else {
    Write-Host "  [FALHA] Arquivo de usuarios NAO encontrado: $UserList" -ForegroundColor Red
    $preReqOk = $false
}

# ── Resultado final dos pre-requisitos ──
Write-Host ""
if (-not $preReqOk) {
    Write-Host "  .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~." -ForegroundColor Red
    Write-Host "  |  PRE-REQUISITOS NAO ATENDIDOS - Script encerrado.       |" -ForegroundColor Red
    Write-Host "  .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~." -ForegroundColor Red
    Write-Host ""
    exit 1
}

Write-Host "  .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~." -ForegroundColor Green
Write-Host "  |  Todos os pre-requisitos OK! Iniciando execucao...       |" -ForegroundColor Green
Write-Host "  .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~." -ForegroundColor Green
Write-Host ""


# ════════════════════════════════════════════════════════════════════
#  TABELA DE DIAS - Mapeamento de nome do dia para indice numerico
#  O AD organiza os 21 bytes comecando no Domingo (indice 0)
#  Cada dia ocupa 3 bytes (24 horas / 8 bits por byte = 3 bytes)
# ════════════════════════════════════════════════════════════════════
$dayMap = @{
    'Sunday'    = 0
    'Monday'    = 1
    'Tuesday'   = 2
    'Wednesday' = 3
    'Thursday'  = 4
    'Friday'    = 5
    'Saturday'  = 6
}
$dayNames = @('Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday')


# ════════════════════════════════════════════════════════════════════
#  FUNCAO: Write-Log
# ────────────────────────────────────────────────────────────────────
#  Grava mensagem no arquivo de log e exibe no console com cores.
#  Niveis: INFO (ciano), SUCCESS (verde), WARNING (amarelo), ERROR (vermelho)
#
#  Parametros:
#    $Message - Texto da mensagem
#    $Level   - Nivel do log (padrao: INFO)
# ════════════════════════════════════════════════════════════════════
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogPath -Value $entry
    switch ($Level) {
        "ERROR"   { Write-Host $entry -ForegroundColor Red }
        "WARNING" { Write-Host $entry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $entry -ForegroundColor Green }
        default   { Write-Host $entry -ForegroundColor Cyan }
    }
}


# ════════════════════════════════════════════════════════════════════
#  FUNCAO: Show-Banner
# ────────────────────────────────────────────────────────────────────
#  Exibe banner visual no console com os parametros atuais.
#  Chamada no inicio da execucao para conferencia rapida.
# ════════════════════════════════════════════════════════════════════
function Show-Banner {
    $banner = @"

    .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.
    |         SET-AD LOGON HOURS  |  by Lyon.                       |
    |         Ailton Rocha        |  v1.0.0                         |
    .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.
    |  Permitido DE       : ${HorarioPermitidoDe}:00 (BRT)                              |
    |  Permitido ATE      : ${HorarioPermitidoAte}:00 (BRT)                             |
    |  Dias aplicados     : Todos                                   |
    |  Fuso horario       : UTC${UTCOffset} (BRT)                           |
    .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.

"@
    Write-Host $banner -ForegroundColor Cyan
}


# ════════════════════════════════════════════════════════════════════
#  FUNCAO: Set-HourBit
# ────────────────────────────────────────────────────────────────────
#  Liga um bit especifico no byte array de 21 bytes do logonHours.
#  Cada dia tem 3 bytes (24 horas). Cada byte tem 8 bits (8 horas).
#
#  Calculo:
#    byteIndex = (dia * 3) + (hora / 8)   --> qual byte
#    bitIndex  = hora % 8                  --> qual bit dentro do byte
#
#  Parametros:
#    $Hours    - Byte array de 21 bytes (passado por referencia)
#    $DayIndex - Indice do dia (0=Domingo, 6=Sabado)
#    $Hour     - Hora UTC (0-23)
# ════════════════════════════════════════════════════════════════════
function Set-HourBit {
    param(
        [byte[]]$Hours,
        [int]$DayIndex,
        [int]$Hour
    )
    $byteIndex = ($DayIndex * 3) + [math]::Floor($Hour / 8)
    $bitIndex  = $Hour % 8
    $Hours[$byteIndex] = $Hours[$byteIndex] -bor (1 -shl $bitIndex)
}


# ════════════════════════════════════════════════════════════════════
#  FUNCAO: Build-LogonHoursArray
# ────────────────────────────────────────────────────────────────────
#  Constroi o byte array de 21 bytes para o atributo logonHours.
#
#  Logica:
#  1. Detecta se o range cruza meia-noite (Start >= End)
#  2. Gera lista de horas locais permitidas
#  3. Para cada dia + hora: converte BRT -> UTC
#  4. Liga o bit correspondente no byte array
#
#  Range normal (ex: 3-23):  horas 3,4,5,...,22
#  Range noturno (ex: 23-3): horas 23,0,1,2 (cruza meia-noite)
#    - Horas apos meia-noite caem automaticamente no dia seguinte
#
#  Parametros:
#    $Start  - Hora inicial permitida (horario local)
#    $End    - Hora final permitida (horario local)
#    $Days   - Array de nomes dos dias permitidos
#    $Offset - Offset UTC do fuso local (BRT = -3)
#
#  Retorna: [byte[]] de 21 bytes pronto para gravar no AD
# ════════════════════════════════════════════════════════════════════
function Build-LogonHoursArray {
    param(
        [int]$Start,
        [int]$End,
        [string[]]$Days,
        [int]$Offset
    )

    [byte[]]$hours = New-Object byte[] 21
    $isOvernight = $Start -ge $End

    # Montar lista de horas locais que serao PERMITIDAS
    $localHours = @()
    if ($isOvernight) {
        # Range noturno: ex Start=23, End=3 → horas 23, 0, 1, 2
        for ($h = $Start; $h -lt 24; $h++) { $localHours += $h }
        for ($h = 0; $h -lt $End; $h++)    { $localHours += $h }
    } else {
        # Range diurno: ex Start=3, End=23 → horas 3, 4, 5, ..., 22
        for ($h = $Start; $h -lt $End; $h++) { $localHours += $h }
    }

    foreach ($day in $Days) {
        $dayIndex = $dayMap[$day]

        foreach ($h in $localHours) {
            # Horas apos meia-noite em range noturno pertencem ao dia SEGUINTE
            $localDay = $dayIndex
            if ($isOvernight -and $h -lt $Start) {
                $localDay = ($dayIndex + 1) % 7
            }

            # Converter hora local para UTC aplicando o offset
            $utcRaw = $h - $Offset
            $utcDay = $localDay

            if ($utcRaw -lt 0) {
                # Hora negativa: volta pro dia anterior
                $utcHour = $utcRaw + 24
                $utcDay  = ($localDay - 1 + 7) % 7
            }
            elseif ($utcRaw -ge 24) {
                # Hora >= 24: avanca pro dia seguinte
                $utcHour = $utcRaw - 24
                $utcDay  = ($localDay + 1) % 7
            }
            else {
                $utcHour = $utcRaw
            }

            Set-HourBit -Hours $hours -DayIndex $utcDay -Hour $utcHour
        }
    }

    return $hours
}


# ════════════════════════════════════════════════════════════════════
#  FUNCAO: Format-LogonHoursReadable
# ────────────────────────────────────────────────────────────────────
#  Converte o byte array de 21 bytes em texto legivel para exibicao.
#  Agrupa horas contíguas em ranges (ex: "06:00-01:59")
#
#  Parametros:
#    $Hours - Byte array de 21 bytes
#    $Label - Rotulo do fuso horario para exibicao (padrao: "UTC")
#
#  Retorna: String formatada com horarios por dia da semana
# ════════════════════════════════════════════════════════════════════
function Format-LogonHoursReadable {
    param(
        [byte[]]$Hours,
        [string]$Label = "UTC"
    )

    $dNames = @('Dom','Seg','Ter','Qua','Qui','Sex','Sab')
    $result = @()

    for ($d = 0; $d -lt 7; $d++) {
        $allowed = @()
        for ($h = 0; $h -lt 24; $h++) {
            $byteIndex = ($d * 3) + [math]::Floor($h / 8)
            $bitIndex  = $h % 8
            if ($Hours[$byteIndex] -band (1 -shl $bitIndex)) {
                $allowed += $h
            }
        }
        if ($allowed.Count -gt 0) {
            # Agrupar horas consecutivas em ranges para leitura limpa
            $ranges = @()
            $rangeStart = $allowed[0]
            $prev = $allowed[0]
            for ($i = 1; $i -lt $allowed.Count; $i++) {
                if ($allowed[$i] -ne $prev + 1) {
                    $ranges += "{0:D2}:00-{1:D2}:59" -f $rangeStart, $prev
                    $rangeStart = $allowed[$i]
                }
                $prev = $allowed[$i]
            }
            $ranges += "{0:D2}:00-{1:D2}:59" -f $rangeStart, $prev
            $result += "      $($dNames[$d]) ($Label): $($ranges -join ', ')"
        }
    }

    return $result -join "`n"
}


# ════════════════════════════════════════════════════════════════════
#  EXECUCAO PRINCIPAL
# ════════════════════════════════════════════════════════════════════
#  Criado por: Ailton Rocha (Lyon.) - github.com/lyonzin
# ════════════════════════════════════════════════════════════════════

Show-Banner

Write-Log "Iniciando configuracao de logon hours"
Write-Log "Arquivo de usuarios: $UserList"

# ── Leitura da lista de usuarios ──
# Suporta .txt (um username por linha) e .csv (coluna SamAccountName)
# Linhas vazias e comentarios (iniciando com #) sao ignorados
$extension = [System.IO.Path]::GetExtension($UserList)
if ($extension -eq '.csv') {
    $users = Import-Csv $UserList | Select-Object -ExpandProperty SamAccountName
} else {
    $users = Get-Content $UserList | Where-Object { $_.Trim() -ne '' -and $_ -notmatch '^\s*#' }
}

$totalUsers = $users.Count
Write-Log "Total de usuarios encontrados: $totalUsers"

if ($totalUsers -eq 0) {
    Write-Log "Nenhum usuario encontrado no arquivo." "ERROR"
    exit 1
}

# ── Construcao do byte array de logon hours ──
$isOvernight = $HorarioPermitidoDe -ge $HorarioPermitidoAte

if ($HorarioPermitidoDe -eq $HorarioPermitidoAte) {
    Write-Log "HorarioPermitidoDe e HorarioPermitidoAte sao iguais ($HorarioPermitidoDe). Nenhuma hora seria liberada." "ERROR"
    exit 1
}

$logonBytes = Build-LogonHoursArray -Start $HorarioPermitidoDe -End $HorarioPermitidoAte -Days $DiasAplicados -Offset $UTCOffset

# ── Exibicao da configuracao aplicada ──
Write-Host ""
if ($isOvernight) {
    Write-Log "RANGE NOTURNO DETECTADO"
    Write-Log "  Logon permitido : ${HorarioPermitidoDe}:00 --> ${HorarioPermitidoAte}:00 (dia seguinte) | BRT"
} else {
    Write-Log "  Logon permitido : ${HorarioPermitidoDe}:00 --> ${HorarioPermitidoAte}:00 | BRT"
}
Write-Log "  Dias aplicados  : $($DiasAplicados -join ', ')"

if ($isOvernight) {
    $extraDays = @()
    foreach ($day in $DiasAplicados) {
        $nextDayIdx = ($dayMap[$day] + 1) % 7
        $nextDayName = $dayNames[$nextDayIdx]
        if ($nextDayName -notin $DiasAplicados -and $nextDayName -notin $extraDays) {
            $extraDays += $nextDayName
        }
    }
    if ($extraDays.Count -gt 0) {
        Write-Log "  Spillover dias   : $($extraDays -join ', ')" "WARNING"
    }
}

Write-Log "  Mapa UTC gravado no AD:"
Write-Log "`n$(Format-LogonHoursReadable $logonBytes 'UTC')`n"

# ── Aplicacao nos usuarios com backup automatico ──
# Para cada usuario:
#   1. Busca no AD e le o logonHours atual
#   2. Salva o valor original no backup (Base64 ou NULL)
#   3. Se ja tem logonHours: Clear primeiro, depois Add (evita erro "attribute already present")
#   4. Se nao tem: Add direto
Write-Host "  .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~." -ForegroundColor DarkCyan
Write-Host "  |  Aplicando restricao nos usuarios...                     |" -ForegroundColor DarkCyan
Write-Host "  .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~." -ForegroundColor DarkCyan
Write-Host ""

$successCount = 0
$failCount = 0
$backupData = @()

foreach ($username in $users) {
    $username = $username.Trim()
    if ([string]::IsNullOrEmpty($username)) { continue }

    try {
        $adUser = Get-ADUser -Identity $username -Properties logonHours -ErrorAction Stop

        # Backup do valor atual antes de alterar
        $currentHours = $adUser.logonHours
        $backupData += [PSCustomObject]@{
            SamAccountName     = $username
            DisplayName        = $adUser.Name
            OriginalLogonHours = if ($currentHours) { [Convert]::ToBase64String($currentHours) } else { "NULL" }
            DataAlteracao      = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        }

        # Aplicar usando modulo AD convencional
        if ($PSCmdlet.ShouldProcess($username, "Definir logon hours")) {
            if ($currentHours) {
                # Atributo ja existe: precisa limpar antes de adicionar o novo valor
                Set-ADUser -Identity $username -Clear logonHours -ErrorAction Stop
                Set-ADUser -Identity $username -Add @{ logonHours = [byte[]]$logonBytes } -ErrorAction Stop
            } else {
                # Atributo nao existe: adicionar direto
                Set-ADUser -Identity $username -Add @{ logonHours = [byte[]]$logonBytes } -ErrorAction Stop
            }
            $successCount++
            Write-Log "  [OK] $username ($($adUser.Name))" "SUCCESS"
        }
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        $failCount++
        Write-Log "  [FALHA] $username - Usuario nao encontrado no AD" "ERROR"
    }
    catch {
        $failCount++
        Write-Log "  [FALHA] $username - $($_.Exception.Message)" "ERROR"
    }
}

# ── Backup em CSV ──
$backupFile = ".\LogonHours_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$backupData | Export-Csv -Path $backupFile -NoTypeInformation -Encoding UTF8

# ── Resumo Final ──
$statusColor = if ($failCount -eq 0) { "Green" } else { "Yellow" }
$resumo = @"

  .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.
  |                    RESUMO DA EXECUCAO                          |
  |            Ailton Rocha (Lyon.)  |  v1.0.0                       |
  .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.
  |  Total de usuarios  : $($totalUsers.ToString().PadRight(40))|
  |  Sucesso             : $($successCount.ToString().PadRight(40))|
  |  Falha               : $($failCount.ToString().PadRight(40))|
  .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.
  |  Arquivo de log      : $($LogPath.PadRight(40))|
  |  Arquivo de backup   : $($backupFile.PadRight(40))|
  .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.
  |  Para desfazer, use Clear-ADLogonHours.ps1 com o backup.      |
  .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.

"@
Write-Host $resumo -ForegroundColor $statusColor
Write-Log "Backup salvo em: $backupFile"
Write-Log "Execucao finalizada. Sucesso: $successCount | Falha: $failCount"

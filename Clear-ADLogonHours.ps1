<#
.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.
|    ____ _                        _    ____  _                            _   _              |
|   / ___| | ___  __ _ _ __      / \  |  _ \| |    ___   __ _  ___  _ _ | | | | ___  _   _    |
|  | |   | |/ _ \/ _` | '__|    / _ \ | | | | |   / _ \ / _` |/ _ \| ' \| |_| |/ _ \| | | |   |
|  | |___| |  __/ (_| | |      / ___ \| |_| | |__| (_) | (_| | (_) | | ||  _  | (_) | |_| |   |
|   \____|_|\___|\__,_|_|     /_/   \_\____/|_____\___/ \__, |\___/|_| ||_| |_|\___/ \__,_|   |
|                                                        |___/                                |
.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.
|  Remocao / Restauracao de Restricao de Horario de Logon via Active Directory                |
.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.
|  Criado por:          Ailton Rocha (Lyon.)                                                  |
|  GitHub:              github.com/lyonzin                                                    |
|  Data de Criacao:     2026-01-27                                                            |
|  Ultima Modificacao:  2026-01-27                                                            |
|  Versao:              1.0.0                                                                 |
.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.
|                                                                                             |
|  DESCRICAO:                                                                                 |
|  Desfaz as restricoes de logon aplicadas pelo Set-ADLogonHours.ps1.                         |
|  Possui dois modos de operacao:                                                             |
|                                                                                             |
|  MODO CLEAR:                                                                                |
|  - Remove o atributo logonHours de cada usuario da lista                                    |
|  - Resultado: usuario pode logar 24/7 sem restricao                                         |
|  - Quando o AD nao tem logonHours, interpreta como "sem restricao"                          |
|                                                                                             |
|  MODO RESTORE:                                                                              |
|  - Restaura o valor ORIGINAL do logonHours a partir do backup CSV                           |
|  - O CSV foi gerado automaticamente pelo Set-ADLogonHours.ps1                               |
|  - Se o original era NULL, remove o atributo (mesmo efeito do Clear)                        |
|  - Se o original era um byte array, restaura exatamente o valor anterior                    |
|                                                                                             |
|  ╔══════════════════════════════════════════════════════════════════╗                       |
|  ║  AVISO DE SEGURANCA:                                             ║                       |
|  ║  Este script SOMENTE modifica o atributo logonHours.             ║                       |
|  ║  Nenhum outro atributo da conta e tocado em nenhuma hipotese.    ║                       |
|  ║  Os unicos cmdlets AD usados sao:                                ║                       |
|  ║    - Get-ADUser    (somente leitura)                             ║                       |
|  ║    - Set-ADUser    (somente -Clear logonHours / -Add logonHours) ║                       |
|  ╚══════════════════════════════════════════════════════════════════╝                       |
|                                                                                             |
.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.

.SYNOPSIS
    Remove ou restaura restricoes de horario de logon no AD.

.EXAMPLE
    .\Clear-ADLogonHours.ps1
#>

[CmdletBinding(SupportsShouldProcess)]
param()

# .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.
# |  PARAMETROS FIXOS - Altere aqui conforme necessidade             |
# .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.
# |                                                                  |
# |  $Modo:                                                          |
# |    "CLEAR"   → Remove restricao de todos da lista (libera 24/7)  |
# |    "RESTORE" → Restaura valor original do backup CSV             |
# |                                                                  |
# |  $ArquivoUsuarios: Lista .txt ou .csv (usado no modo CLEAR)      |
# |  $ArquivoBackup:  CSV do Set-ADLogonHours (usado no modo RESTORE)|
# |                                                                  |
# .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.
$Modo              = "CLEAR"       # "CLEAR" ou "RESTORE"
$ArquivoUsuarios   = ".\usuarios.txt"  # Altere para o caminho da sua lista
$ArquivoBackup     = ""            # Preencher com caminho do CSV de backup para modo RESTORE
$LogPath           = ".\ClearLogonHours_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
# .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.


# ════════════════════════════════════════════════════════════════════
#  PRE-REQUISITOS
# ────────────────────────────────────────────────────────────────────
#  Verifica ANTES de executar qualquer coisa:
#    1. PowerShell rodando como Administrador
#    2. Modulo ActiveDirectory disponivel (oferece instalar se ausente)
#    3. Maquina com acesso a um Domain Controller
#    4. Arquivo de entrada existe (usuarios ou backup, conforme o modo)
#    5. Modo valido (CLEAR ou RESTORE)
#
#  Se qualquer pre-requisito falhar, o script PARA com mensagem clara.
# ════════════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "  .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~." -ForegroundColor DarkYellow
Write-Host "  |  Verificando pre-requisitos...                          |" -ForegroundColor DarkYellow
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

# ── 4. Validar modo de operacao ──
$Modo = $Modo.ToUpper().Trim()
if ($Modo -notin @("CLEAR","RESTORE")) {
    Write-Host "  [FALHA] Modo invalido: '$Modo'. Use 'CLEAR' ou 'RESTORE'." -ForegroundColor Red
    $preReqOk = $false
} else {
    Write-Host "  [OK] Modo de operacao: $Modo" -ForegroundColor Green
}

# ── 5. Verificar se arquivo de entrada existe ──
if ($Modo -eq "CLEAR") {
    if (Test-Path $ArquivoUsuarios) {
        $lineCount = (Get-Content $ArquivoUsuarios | Where-Object { $_.Trim() -ne '' -and $_ -notmatch '^\s*#' }).Count
        Write-Host "  [OK] Arquivo de usuarios encontrado ($lineCount matriculas)" -ForegroundColor Green
    } else {
        Write-Host "  [FALHA] Arquivo de usuarios NAO encontrado: $ArquivoUsuarios" -ForegroundColor Red
        $preReqOk = $false
    }
} elseif ($Modo -eq "RESTORE") {
    if ([string]::IsNullOrWhiteSpace($ArquivoBackup)) {
        Write-Host "  [FALHA] Variavel `$ArquivoBackup esta vazia. Informe o caminho do CSV de backup." -ForegroundColor Red
        $preReqOk = $false
    } elseif (Test-Path $ArquivoBackup) {
        $backupLineCount = (Import-Csv $ArquivoBackup).Count
        Write-Host "  [OK] Arquivo de backup encontrado ($backupLineCount registros)" -ForegroundColor Green
    } else {
        Write-Host "  [FALHA] Arquivo de backup NAO encontrado: $ArquivoBackup" -ForegroundColor Red
        $preReqOk = $false
    }
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
Write-Host "  |  Todos os pre-requisitos OK! Iniciando execucao...      |" -ForegroundColor Green
Write-Host "  .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~." -ForegroundColor Green
Write-Host ""


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
#  Exibe banner visual no console com o modo de operacao atual.
#  Chamada no inicio da execucao para conferencia rapida.
#
#  Parametros: nenhum (usa variaveis do escopo do script)
# ════════════════════════════════════════════════════════════════════
function Show-Banner {
    $modoDescricao = if ($Modo -eq "CLEAR") {
        "Remover restricoes (liberar 24/7)"
    } else {
        "Restaurar valores originais do backup"
    }

    $arquivoInfo = if ($Modo -eq "CLEAR") { $ArquivoUsuarios } else { $ArquivoBackup }

    $banner = @"

    .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.
    |       CLEAR-AD LOGON HOURS  |  by Lyon.                      |
    |       Ailton Rocha          |  v1.0.0                        |
    .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.
    |  Modo de operacao  : $($modoDescricao.PadRight(41))|
    |  Arquivo de entrada: $($arquivoInfo.PadRight(41))|
    .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.
    |  ATRIBUTO MODIFICADO: logonHours (SOMENTE ESTE)              |
    .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.

"@
    Write-Host $banner -ForegroundColor Cyan
}


# ════════════════════════════════════════════════════════════════════
#  FUNCAO: Clear-LogonHoursAttribute
# ────────────────────────────────────────────────────────────────────
#  Remove o atributo logonHours de um usuario no AD.
#  Quando o AD nao possui o atributo logonHours, o usuario
#  pode logar em qualquer horario (24/7).
#
#  SEGURANCA: Usa SOMENTE "Set-ADUser -Clear logonHours".
#  Nenhum outro atributo e tocado.
#
#  Parametros:
#    $Username - SamAccountName do usuario no AD
#
#  Retorna:
#    $true se operacao foi bem-sucedida, $false caso contrario
# ════════════════════════════════════════════════════════════════════
function Clear-LogonHoursAttribute {
    param([string]$Username)

    try {
        # Leitura apenas para confirmar que o usuario existe
        # e para verificar se ja tem logonHours definido
        $adUser = Get-ADUser -Identity $Username -Properties logonHours -ErrorAction Stop
        $currentHours = $adUser.logonHours

        if ($null -eq $currentHours) {
            # Atributo ja esta vazio - usuario ja nao tem restricao
            Write-Log "  [SKIP] $Username ($($adUser.Name)) - Ja sem restricao (logonHours vazio)" "WARNING"
            return $true
        }

        if ($PSCmdlet.ShouldProcess($Username, "Limpar logonHours (liberar 24/7)")) {
            # UNICA operacao de escrita: remover o atributo logonHours
            Set-ADUser -Identity $Username -Clear logonHours -ErrorAction Stop
            Write-Log "  [OK] $Username ($($adUser.Name)) - Restricao removida (24/7)" "SUCCESS"
        }
        return $true
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        Write-Log "  [FALHA] $Username - Usuario nao encontrado no AD" "ERROR"
        return $false
    }
    catch {
        Write-Log "  [FALHA] $Username - $($_.Exception.Message)" "ERROR"
        return $false
    }
}


# ════════════════════════════════════════════════════════════════════
#  FUNCAO: Restore-LogonHoursAttribute
# ────────────────────────────────────────────────────────────────────
#  Restaura o atributo logonHours de um usuario ao valor original
#  salvo no backup CSV (gerado pelo Set-ADLogonHours.ps1).
#
#  Dois cenarios possiveis:
#    1. Original era NULL → Remove o atributo (libera 24/7)
#    2. Original era Base64 → Decodifica e grava o byte array original
#
#  SEGURANCA:
#  - Usa SOMENTE "Set-ADUser -Clear logonHours" e "-Add logonHours"
#  - Usa o padrao Clear → Add para evitar o erro "attribute already present"
#  - Nenhum outro atributo e tocado em nenhuma hipotese
#
#  Parametros:
#    $Username           - SamAccountName do usuario
#    $OriginalLogonHours - Valor original (Base64 string ou "NULL")
#
#  Retorna:
#    $true se operacao foi bem-sucedida, $false caso contrario
# ════════════════════════════════════════════════════════════════════
function Restore-LogonHoursAttribute {
    param(
        [string]$Username,
        [string]$OriginalLogonHours
    )

    try {
        # Leitura apenas para confirmar existencia e estado atual
        $adUser = Get-ADUser -Identity $Username -Properties logonHours -ErrorAction Stop
        $currentHours = $adUser.logonHours

        if ($OriginalLogonHours -eq "NULL") {
            # ── Cenario 1: Original era NULL (sem restricao) ──
            if ($null -eq $currentHours) {
                Write-Log "  [SKIP] $Username ($($adUser.Name)) - Ja sem restricao (original era NULL)" "WARNING"
                return $true
            }

            if ($PSCmdlet.ShouldProcess($Username, "Limpar logonHours (original era NULL)")) {
                Set-ADUser -Identity $Username -Clear logonHours -ErrorAction Stop
                Write-Log "  [OK] $Username ($($adUser.Name)) - Restaurado (NULL = sem restricao)" "SUCCESS"
            }
        } else {
            # ── Cenario 2: Original era um byte array ──
            [byte[]]$originalBytes = [Convert]::FromBase64String($OriginalLogonHours)

            if ($PSCmdlet.ShouldProcess($Username, "Restaurar logonHours original")) {
                # Padrao Clear → Add (evita erro "attribute already present")
                if ($currentHours) {
                    # Atributo existe: precisa limpar antes de adicionar
                    Set-ADUser -Identity $Username -Clear logonHours -ErrorAction Stop
                }
                # Adicionar o valor original
                Set-ADUser -Identity $Username -Add @{ logonHours = [byte[]]$originalBytes } -ErrorAction Stop
                Write-Log "  [OK] $Username ($($adUser.Name)) - Restaurado (valor original do backup)" "SUCCESS"
            }
        }
        return $true
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        Write-Log "  [FALHA] $Username - Usuario nao encontrado no AD" "ERROR"
        return $false
    }
    catch {
        Write-Log "  [FALHA] $Username - $($_.Exception.Message)" "ERROR"
        return $false
    }
}


# ════════════════════════════════════════════════════════════════════
#  EXECUCAO PRINCIPAL
# ════════════════════════════════════════════════════════════════════
#  Criado por: Ailton Rocha (Lyon.) - github.com/lyonzin
#
#  ATENCAO: Este bloco SOMENTE modifica o atributo logonHours.
#  Nenhum outro atributo (senha, grupo, OU, displayName, etc.)
#  e lido para escrita ou alterado em nenhuma circunstancia.
# ════════════════════════════════════════════════════════════════════

Show-Banner

$successCount = 0
$failCount    = 0
$skipCount    = 0
$totalUsers   = 0

if ($Modo -eq "RESTORE") {
    # ══════════════════════════════════════════════════════════════
    #  MODO RESTORE: Restaurar valores originais do backup CSV
    # ══════════════════════════════════════════════════════════════

    Write-Log "MODO RESTORE - Restaurando valores originais do backup"
    Write-Log "Arquivo de backup: $ArquivoBackup"

    Write-Host "  .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~." -ForegroundColor DarkCyan
    Write-Host "  |  Restaurando logonHours dos usuarios (backup CSV)...    |" -ForegroundColor DarkCyan
    Write-Host "  .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~." -ForegroundColor DarkCyan
    Write-Host ""

    $backupData = Import-Csv $ArquivoBackup
    $totalUsers = $backupData.Count
    Write-Log "Total de usuarios no backup: $totalUsers"

    foreach ($row in $backupData) {
        $username = $row.SamAccountName

        $result = Restore-LogonHoursAttribute -Username $username -OriginalLogonHours $row.OriginalLogonHours

        if ($result) {
            $successCount++
        } else {
            $failCount++
        }
    }

} else {
    # ══════════════════════════════════════════════════════════════
    #  MODO CLEAR: Remover restricoes (liberar 24/7)
    # ──────────────────────────────────────────────────────────────
    #  Le a lista de usuarios (.txt ou .csv) e remove o atributo
    #  logonHours de cada um, liberando logon em qualquer horario.
    # ══════════════════════════════════════════════════════════════

    Write-Log "MODO CLEAR - Removendo todas as restricoes (24/7)"
    Write-Log "Arquivo de usuarios: $ArquivoUsuarios"

    Write-Host "  .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~." -ForegroundColor DarkCyan
    Write-Host "  |  Removendo restricoes de logon dos usuarios...          |" -ForegroundColor DarkCyan
    Write-Host "  .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~." -ForegroundColor DarkCyan
    Write-Host ""

    # ── Leitura da lista de usuarios ──
    # Suporta .txt (um username por linha) e .csv (coluna SamAccountName)
    # Linhas vazias e comentarios (iniciando com #) sao ignorados
    $extension = [System.IO.Path]::GetExtension($ArquivoUsuarios)
    if ($extension -eq '.csv') {
        $users = Import-Csv $ArquivoUsuarios | Select-Object -ExpandProperty SamAccountName
    } else {
        $users = Get-Content $ArquivoUsuarios | Where-Object { $_.Trim() -ne '' -and $_ -notmatch '^\s*#' }
    }

    $totalUsers = $users.Count
    Write-Log "Total de usuarios encontrados: $totalUsers"

    if ($totalUsers -eq 0) {
        Write-Log "Nenhum usuario encontrado no arquivo." "ERROR"
        exit 1
    }

    foreach ($username in $users) {
        $username = $username.Trim()
        if ([string]::IsNullOrEmpty($username)) { continue }

        $result = Clear-LogonHoursAttribute -Username $username

        if ($result) {
            $successCount++
        } else {
            $failCount++
        }
    }
}


# ════════════════════════════════════════════════════════════════════
#  RESUMO FINAL
# ────────────────────────────────────────────────────────────────────
#  Exibe box visual com resultado da execucao e caminho do log.
# ════════════════════════════════════════════════════════════════════

$modoResumo = if ($Modo -eq "CLEAR") { "CLEAR (Liberar 24/7)" } else { "RESTORE (Backup CSV)" }
$statusColor = if ($failCount -eq 0) { "Green" } else { "Yellow" }

$resumo = @"

  .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.
  |                    RESUMO DA EXECUCAO                         |
  |            Ailton Rocha (Lyon.)  |  v1.0.0                    |
  .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.
  |  Modo de operacao   : $($modoResumo.PadRight(40))|
  |  Total de usuarios  : $($totalUsers.ToString().PadRight(40))|
  |  Sucesso             : $($successCount.ToString().PadRight(40))|
  |  Falha               : $($failCount.ToString().PadRight(40))|
  .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.
  |  Atributo modificado : logonHours (SOMENTE ESTE)             |
  |  Arquivo de log      : $($LogPath.PadRight(40))      | 
  .~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.

"@
Write-Host $resumo -ForegroundColor $statusColor
Write-Log "Execucao finalizada. Modo: $Modo | Sucesso: $successCount | Falha: $failCount"

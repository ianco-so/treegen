<#
.SYNOPSIS
    Script para sincronizar bancos de dados (Dump Remoto -> Restore Local -> Validação).
    v2.0 - Com validação de dados
#>

param (
    [string]$Project = "mynps"
)

# Cores
$Green  = "Green"
$Red    = "Red"
$Cyan   = "Cyan"
$Yellow = "Yellow"

# --- FUNÇÃO AUXILIAR DE COMPARAÇÃO ---
function Get-TableCounts {
    param ($Container, $HostAddr, $User, $DB, $Pass)
    
    # Query: Pega nome da tabela e contagem de linhas (estatística)
    # O 'COPY ... TO STDOUT WITH CSV' garante que o PowerShell receba dados limpos
    $Query = "COPY (SELECT relname, n_live_tup FROM pg_stat_user_tables WHERE schemaname = 'public' ORDER BY 1) TO STDOUT WITH CSV"
    
    try {
        $CsvData = docker exec -e PGPASSWORD="$Pass" $Container psql -h $HostAddr -U $User -d $DB -c "$Query"
        
        # Converte o CSV recebido em um Hash Table (Dicionário) do PowerShell
        $TableMap = @{}
        $CsvData | ConvertFrom-Csv -Header "Table", "Count" | ForEach-Object {
            $TableMap[$_.Table] = [int]$_.Count
        }
        return $TableMap
    }
    catch {
        Write-Host "Erro ao obter contagem de linhas do host $HostAddr" -ForegroundColor $Red
        return @{}
    }
}

# --- PROJETO MYNPS ---
function Sync-MyNPS {
    Write-Host "`n>>> [1/4] Configurando: MY NPS (Postgres)" -ForegroundColor $Cyan
    
    # Configurações
    $ContainerName = "postgres-gertec"
    $RemoteHost    = "mynps-apps-databasedev.cxih0mprptnf.us-west-2.rds.amazonaws.com"
    $RemoteUser    = "user_eld_test"
    $RemoteDB      = "mynpsappsdb"
    $RemotePass    = "eld-test_2024"
    
    $LocalHost     = "localhost" # interno do docker
    $LocalUser     = "developer"
    $LocalDB       = "mynps_gertec_db"
    $DumpFile      = "backup_temp.sql"

    # 1. DUMP
    Write-Host ">>> [2/4] Baixando dados da AWS..." -NoNewline
    try {
        docker exec -e PGPASSWORD="$RemotePass" $ContainerName pg_dump -h $RemoteHost -U $RemoteUser --no-owner --no-acl --clean --if-exists $RemoteDB > $DumpFile
        if ((Get-Item $DumpFile).Length -eq 0) { throw "Arquivo vazio." }
        Write-Host " [OK]" -ForegroundColor $Green
    }
    catch { Write-Host " [FALHA]" -ForegroundColor $Red; return }

    # 2. RESTORE
    Write-Host ">>> [3/4] Restaurando no Docker Local..." -NoNewline
    try {
        Get-Content $DumpFile | docker exec -i $ContainerName psql -U $LocalUser -d $LocalDB | Out-Null
        # IMPORTANTE: Atualiza as estatísticas do banco local para a contagem bater
        docker exec -i $ContainerName psql -U $LocalUser -d $LocalDB -c "ANALYZE;" | Out-Null
        Write-Host " [OK]" -ForegroundColor $Green
    }
    catch { Write-Host " [FALHA]" -ForegroundColor $Red; return }

    # 3. VALIDAÇÃO (O Pulo do Gato)
    Write-Host ">>> [4/4] Validando Integridade dos Dados..." -ForegroundColor $Cyan
    
    # Pega contagem da AWS e do Local
    Write-Host "    Coletando métricas..."
    $RemoteStats = Get-TableCounts -Container $ContainerName -HostAddr $RemoteHost -User $RemoteUser -DB $RemoteDB -Pass $RemotePass
    $LocalStats  = Get-TableCounts -Container $ContainerName -HostAddr $LocalHost  -User $LocalUser  -DB $LocalDB  -Pass $LocalUser # Senha local geralmente é ignorada se for trust, mas enviamos user

    # Compara
    $Errors = 0
    foreach ($Table in $RemoteStats.Keys) {
        $RCount = $RemoteStats[$Table]
        $LCount = $LocalStats[$Table]

        if ($null -eq $LCount) {
            Write-Host "    [ERRO] Tabela '$Table' não existe no Local!" -ForegroundColor $Red
            $Errors++
        }
        elseif ($RCount -ne $LCount) {
            Write-Host "    [DIFERENÇA] $Table : AWS ($RCount) vs Local ($LCount)" -ForegroundColor $Yellow
            $Errors++
        }
    }

    # Limpeza
    Remove-Item $DumpFile -ErrorAction SilentlyContinue

    # Resultado Final
    if ($Errors -eq 0) {
        Write-Host "`n>>> SUCESSO TOTAL! O banco local é um clone perfeito da AWS. 🚀" -ForegroundColor $Green
    } else {
        Write-Host "`n>>> AVISO: O processo terminou, mas houve $Errors divergências nas contagens." -ForegroundColor $Yellow
    }
}

# --- ROTEADOR ---
switch ($Project.ToLower()) {
    "mynps" { Sync-MyNPS }
    Default { Write-Host "Projeto '$Project' desconhecido." -ForegroundColor $Red }
}
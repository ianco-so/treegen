param (
    [Parameter(Mandatory=$true)]
    [string]$RootPath,

    [switch]$ShowContent
)

function Show-Tree {
    param (
        [string]$Path,
        [string]$Indent = "",
        [bool]$IsLast = $true
    )

    $item = Get-Item $Path
    $prefix = if ($IsLast) { "└── " } else { "├── " }
    Write-Output "$Indent$prefix$($item.Name)"

    # Corrigido: definir $branchIndent com if separado
    if ($IsLast) {
        $branchIndent = "    "
    } else {
        $branchIndent = "│   "
    }
    $newIndent = $Indent + $branchIndent

    if ($item.PSIsContainer) {
        $children = Get-ChildItem $item.FullName
        $count = $children.Count
        for ($i = 0; $i -lt $count; $i++) {
            $child = $children[$i]
            $isLastChild = ($i -eq ($count - 1))
            Show-Tree -Path $child.FullName -Indent $newIndent -IsLast $isLastChild
        }
    }
    else {
        if ($ShowContent) {
            try {
                $content = Get-Content $item.FullName -ErrorAction Stop
                foreach ($line in $content) {
                    Write-Output "$newIndent    $line"
                }
            } catch {
                Write-Output "$newIndent    [Erro ao ler o conteúdo do arquivo]"
            }
        }
    }
}

# Verificação inicial
if (-Not (Test-Path $RootPath)) {
    Write-Output "O caminho especificado não existe."
    exit
}

$RootItem = Get-Item $RootPath
Write-Output "$($RootItem.Name)/"
$children = Get-ChildItem $RootPath
$count = $children.Count

for ($i = 0; $i -lt $count; $i++) {
    $child = $children[$i]
    $isLast = ($i -eq ($count - 1))
    Show-Tree -Path $child.FullName -Indent "" -IsLast $isLast
}

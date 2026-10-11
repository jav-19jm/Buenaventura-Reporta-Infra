# Rellena en .env los secretos que estén vacíos (APP_KEY, JWT_SECRET, claves de
# Reverb y contraseñas). No toca los valores que ya existan.
#   powershell -ExecutionPolicy Bypass -File scripts\generar-secretos.ps1
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

if (-not (Test-Path .env)) { Copy-Item .env.example .env }

function Get-Hex([int]$bytes) {
    $buffer = New-Object byte[] $bytes
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($buffer)
    ($buffer | ForEach-Object { $_.ToString('x2') }) -join ''
}

function Get-Base64([int]$bytes) {
    $buffer = New-Object byte[] $bytes
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($buffer)
    [Convert]::ToBase64String($buffer)
}

$valores = [ordered]@{
    'APP_KEY'           = 'base64:' + (Get-Base64 32)
    'JWT_SECRET'        = Get-Hex 32
    'DB_PASSWORD'       = Get-Hex 16
    'REDIS_PASSWORD'    = Get-Hex 16
    'REVERB_APP_KEY'    = Get-Hex 10
    'REVERB_APP_SECRET' = Get-Hex 20
    'ADMIN_PASSWORD'    = Get-Hex 6
}

$lineas = Get-Content .env
Write-Host 'Generando secretos en .env...'
foreach ($clave in $valores.Keys) {
    $lineas = $lineas | ForEach-Object {
        if ($_ -eq "$clave=") { Write-Host "  $clave generado"; "$clave=$($valores[$clave])" } else { $_ }
    }
}
# UTF-8 sin BOM y finales de línea LF, como espera Docker Compose
[System.IO.File]::WriteAllText((Join-Path (Get-Location) '.env'), (($lineas -join "`n") + "`n"))

Write-Host 'Listo. Contraseña del administrador inicial:'
Get-Content .env | Where-Object { $_ -like 'ADMIN_PASSWORD=*' }

param([ValidateSet('start','status','stop')][string]$Acao = 'status')
$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '..')
$tmp = New-TemporaryFile
$payload = New-TemporaryFile
try {
    $fn = terraform output -raw control_function
    if ($LASTEXITCODE -ne 0) { throw 'Não foi possível ler o estado do Terraform.' }
    [IO.File]::WriteAllText($payload.FullName, (@{action=$Acao} | ConvertTo-Json -Compress))
    $response = aws lambda invoke --region sa-east-1 --function-name $fn --payload "fileb://$($payload.FullName)" --no-cli-pager --output json $tmp.FullName
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao invocar a Lambda.' }
    $meta = $response | ConvertFrom-Json
    $body = Get-Content $tmp.FullName -Raw
    if ($meta.FunctionError) { throw $body }
    $body
} finally {
    Remove-Item -LiteralPath $tmp.FullName,$payload.FullName -Force
    Pop-Location
}

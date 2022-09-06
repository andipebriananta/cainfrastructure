Param (
    [string]$Location = 'southeastasia',
    [string]$AADTenant = 'columbiaasia.com',
    [string]$PublicDnsZone = 'columbiaasia.com',
    [string]$privateDnsZoneName ='columbiaasia.com',
    # [string]$PublicDnsZoneResourceGroup = 'external-dns-zones-rg',
    [string]$Prefix = 'UAT',
    [string]$PfxCertificateName = 'columbiaasia.pfx',
    [string]$CertificateName = 'columbiaasia.cer',
    [SecureString]$CertificatePassword = $('WmStYvUS#959' | ConvertTo-SecureString -AsPlainText -Force),
    [string]$AksAdminGroupObjectId = "d289b9ad-4e1b-44bb-97ad-4fe645eddc19", #AKS-ADMIN-GROUP created in the Azure AD
    # [string]$AksAdminGroupObjectId = "f6a900e2-df11-43e7-ba3e-22be99d3cede",
    # [string]$ResourceGroupName = "ag-apim-aks-$Location-simple-2-rg",
    [string]$ResourceGroupName = "UAT-MCARE21-RG",
    [string]$ReactSpaSvcIp = '2.2.2.2'
)

$deploymentName = 'uat-mcare21-deploy-01'
$keyVaultDeploymentName = 'kv-deploy'

$ErrorActionPreference = 'stop'

# create resource group
$rg = New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Force

# create key vault & upload SSL certificate
Write-Host -Object "Deploying Key Vault"
New-AzResourceGroupDeployment `
    -Name $keyVaultDeploymentName `
    -ResourceGroupName $rg.ResourceGroupName `
    -Mode Incremental `
    -templateFile ../infra/modules/keyvault.bicep `
    -keyVaultAdminObjectId $(Get-AzADUser -SignedIn | Select-Object -ExpandProperty Id) `
    -location $Location `
    -deployUserAccessPolicy $false

# get deployment output
$kvDeployment = Get-AzResourceGroupDeployment -Name $keyVaultDeploymentName -ResourceGroupName $rg.ResourceGroupName

# upload public tls certificate to Key Vault
Write-Host -Object "Uploading TLS certificate to Key Vault"
$tlsCertificate = Import-AzKeyVaultCertificate -VaultName $kvDeployment.Outputs.keyVaultName.value `
    -Name 'public-tls-certificate' `
    -Password $CertificatePassword `
    -FilePath ../certs/$PfxCertificateName

# deploy bicep template
Write-Host -Object "Deploying infrastructure"
New-AzResourceGroupDeployment `
    -Name $deploymentName `
    -ResourceGroupName $rg.ResourceGroupName `
    -TemplateParameterFile  ../infra/main.parameters.json `
    -Mode Incremental `
    -templateFile ../infra/main.bicep `
    -location $Location `
    -aksAdminGroupObjectId $AksAdminGroupObjectId `
    -kubernetesSpaIpAddress $reactSpaSvcIp `
    -keyVaultName $kvDeployment.Outputs.keyVaultName.value `
    -tlsCertSecretId $($tlsCertificate.SecretId | ConvertTo-SecureString -AsPlainText -Force) `
    -Verbose

# get deployment output
$deployment = Get-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $rg.ResourceGroupName

# stop & start the app gateway for it to get the updated DNS zone!!!!
$appgwy = Get-AzApplicationGateway -Name $deployment.Outputs.appGwyName.value -ResourceGroupName $rg.ResourceGroupName

Write-Host -Object "Stopping App Gateway"
Stop-AzApplicationGateway -ApplicationGateway $appgwy

Write-Host -Object "Starting App Gateway"
Start-AzApplicationGateway -ApplicationGateway $appgwy

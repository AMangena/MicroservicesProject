# =============================================================
# MicroservicesProject - Azure Deployment Script
# Builds images, pushes to ACR, deploys to Azure Container Apps
# =============================================================

# -------------------- CONFIGURATION -------------------------
$RESOURCE_GROUP    = "microservices-rg"
$LOCATION          = "southafricanorth"
$ACR_NAME          = "microservicesacr2026"
$ENVIRONMENT_NAME  = "microservices-env"
$SQL_SERVER        = "microservices-2026.database.windows.net"
$SQL_DB            = "MicroservicesDb"
$SQL_USER          = "Mangena"
$SQL_PASSWORD      = $env:DB_PASSWORD

$SERVICES = @(
    @{ Name = "product-api";          Image = "product-api";          Port = 8080; External = $true  },
    @{ Name = "order-api";            Image = "order-api";            Port = 8080; External = $true  },
    @{ Name = "payment-service";      Image = "payment-service";      Port = 0;    External = $false },
    @{ Name = "notification-service"; Image = "notification-service"; Port = 0;    External = $false }
)
# -------------------------------------------------------------

$CONNECTION_STRING = "Server=tcp:$SQL_SERVER,1433;Initial Catalog=$SQL_DB;Persist Security Info=False;User ID=$SQL_USER;Password=$SQL_PASSWORD;MultipleActiveResultSets=True;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " MicroservicesProject Azure Deployment" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------------
# STEP 1 - Build all Docker images using docker-compose
# ------------------------------------------------------------------
Write-Host "[1/7] Building all Docker images..." -ForegroundColor Yellow
docker-compose build
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: docker-compose build failed." -ForegroundColor Red; exit 1 }
Write-Host "      All images built successfully." -ForegroundColor Green

# ------------------------------------------------------------------
# STEP 2 - Login to Azure
# ------------------------------------------------------------------
Write-Host ""
Write-Host "[2/7] Logging in to Azure..." -ForegroundColor Yellow
az login
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: Azure login failed." -ForegroundColor Red; exit 1 }

# ------------------------------------------------------------------
# STEP 3 - Create Resource Group
# ------------------------------------------------------------------
Write-Host ""
Write-Host "[3/7] Ensuring resource group '$RESOURCE_GROUP' exists..." -ForegroundColor Yellow
az group create --name $RESOURCE_GROUP --location $LOCATION --output none
Write-Host "      Resource group ready." -ForegroundColor Green

# ------------------------------------------------------------------
# STEP 4 - Create Azure Container Registry
# ------------------------------------------------------------------
Write-Host ""
Write-Host "[4/7] Ensuring Azure Container Registry '$ACR_NAME' exists..." -ForegroundColor Yellow
az acr create `
    --resource-group $RESOURCE_GROUP `
    --name $ACR_NAME `
    --sku Basic `
    --admin-enabled true `
    --output none

$ACR_LOGIN_SERVER = az acr show --name $ACR_NAME --query loginServer --output tsv
$ACR_USERNAME     = az acr credential show --name $ACR_NAME --query username --output tsv
$ACR_PASSWORD     = az acr credential show --name $ACR_NAME --query "passwords[0].value" --output tsv
Write-Host "      ACR ready: $ACR_LOGIN_SERVER" -ForegroundColor Green

# ------------------------------------------------------------------
# STEP 5 - Tag and Push all images to ACR
# ------------------------------------------------------------------
Write-Host ""
Write-Host "[5/7] Logging Docker into ACR and pushing images..." -ForegroundColor Yellow
docker login $ACR_LOGIN_SERVER --username $ACR_USERNAME --password $ACR_PASSWORD

foreach ($svc in $SERVICES) {
    $localTag = "microservicesproject-$($svc.Image):latest"
    $acrTag   = "$ACR_LOGIN_SERVER/$($svc.Image):latest"

    Write-Host "      Tagging  $localTag  ->  $acrTag" -ForegroundColor Gray
    docker tag $localTag $acrTag

    Write-Host "      Pushing  $acrTag ..." -ForegroundColor Gray
    docker push $acrTag
    if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: Push failed for $($svc.Image)" -ForegroundColor Red; exit 1 }
    Write-Host "      Pushed $($svc.Image)" -ForegroundColor Green
}

# ------------------------------------------------------------------
# STEP 6 - Create Container Apps Environment
# ------------------------------------------------------------------
Write-Host ""
Write-Host "[6/7] Ensuring Container Apps Environment '$ENVIRONMENT_NAME' exists..." -ForegroundColor Yellow
az containerapp env create `
    --name $ENVIRONMENT_NAME `
    --resource-group $RESOURCE_GROUP `
    --location $LOCATION `
    --output none
Write-Host "      Environment ready." -ForegroundColor Green

# ------------------------------------------------------------------
# STEP 7 - Deploy each service as a Container App
# ------------------------------------------------------------------
Write-Host ""
Write-Host "[7/7] Deploying Container Apps..." -ForegroundColor Yellow

foreach ($svc in $SERVICES) {
    $acrTag  = "$ACR_LOGIN_SERVER/$($svc.Image):latest"
    $appName = $svc.Name

    Write-Host ""
    Write-Host "      Deploying '$appName'..." -ForegroundColor Gray

    if ($svc.External) {
        az containerapp create `
            --name $appName `
            --resource-group $RESOURCE_GROUP `
            --environment $ENVIRONMENT_NAME `
            --image $acrTag `
            --registry-server $ACR_LOGIN_SERVER `
            --registry-username $ACR_USERNAME `
            --registry-password $ACR_PASSWORD `
            --target-port $svc.Port `
            --ingress external `
            --min-replicas 1 `
            --max-replicas 3 `
            --cpu 0.5 `
            --memory 1.0Gi `
            --env-vars "ConnectionStrings__DefaultConnection=$CONNECTION_STRING" `
            --output none
    } else {
        az containerapp create `
            --name $appName `
            --resource-group $RESOURCE_GROUP `
            --environment $ENVIRONMENT_NAME `
            --image $acrTag `
            --registry-server $ACR_LOGIN_SERVER `
            --registry-username $ACR_USERNAME `
            --registry-password $ACR_PASSWORD `
            --min-replicas 1 `
            --max-replicas 3 `
            --cpu 0.5 `
            --memory 1.0Gi `
            --env-vars "ConnectionStrings__DefaultConnection=$CONNECTION_STRING" `
            --output none
    }

    if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: Deployment failed for $appName" -ForegroundColor Red; exit 1 }
    Write-Host "      Deployed $appName" -ForegroundColor Green
}

# ------------------------------------------------------------------
# DONE - Print URLs
# ------------------------------------------------------------------
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " Deployment Complete!" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Your public API URLs:" -ForegroundColor White
foreach ($svc in $SERVICES | Where-Object { $_.External }) {
    $url = az containerapp show `
        --name $svc.Name `
        --resource-group $RESOURCE_GROUP `
        --query "properties.configuration.ingress.fqdn" `
        --output tsv
    Write-Host "  $($svc.Name): https://$url/swagger" -ForegroundColor Green
}
Write-Host ""

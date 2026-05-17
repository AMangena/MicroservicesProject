#!/bin/bash
# =============================================================
# MicroservicesProject - Azure Deployment Script
# Pushes images to ACR and deploys to Azure Container Apps
# =============================================================

# -------------------- CONFIGURATION -------------------------
RESOURCE_GROUP="microservices-rg"
LOCATION="southafricanorth"
ACR_NAME="microservicesacr2026"
ENVIRONMENT_NAME="microservices-env"
SQL_SERVER="microservices-2026.database.windows.net"
SQL_DB="MicroservicesDb"
SQL_USER="Mangena"
SQL_PASSWORD="${DB_PASSWORD}"
# -------------------------------------------------------------

CONNECTION_STRING="Server=tcp:${SQL_SERVER},1433;Initial Catalog=${SQL_DB};Persist Security Info=False;User ID=${SQL_USER};Password=${SQL_PASSWORD};MultipleActiveResultSets=True;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"

echo ""
echo "============================================="
echo " MicroservicesProject Azure Deployment"
echo "============================================="
echo ""

# ------------------------------------------------------------------
# STEP 1 — Login to Azure
# ------------------------------------------------------------------
echo "[1/6] Logging in to Azure..."
az login
if [ $? -ne 0 ]; then echo "ERROR: Azure login failed."; exit 1; fi

# ------------------------------------------------------------------
# STEP 2 — Create Resource Group
# ------------------------------------------------------------------
echo ""
echo "[2/6] Ensuring resource group '${RESOURCE_GROUP}' exists..."
az group create --name $RESOURCE_GROUP --location $LOCATION --output none
echo "      Resource group ready."

# ------------------------------------------------------------------
# STEP 3 — Create Azure Container Registry
# ------------------------------------------------------------------
echo ""
echo "[3/6] Ensuring Azure Container Registry '${ACR_NAME}' exists..."
az acr create \
    --resource-group $RESOURCE_GROUP \
    --name $ACR_NAME \
    --sku Basic \
    --admin-enabled true \
    --output none

ACR_LOGIN_SERVER=$(az acr show --name $ACR_NAME --query loginServer --output tsv)
ACR_USERNAME=$(az acr credential show --name $ACR_NAME --query username --output tsv)
ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query "passwords[0].value" --output tsv)
echo "      ACR ready: ${ACR_LOGIN_SERVER}"

# ------------------------------------------------------------------
# STEP 4 — Tag and Push all images to ACR
# ------------------------------------------------------------------
echo ""
echo "[4/6] Logging Docker into ACR and pushing images..."
docker login $ACR_LOGIN_SERVER --username $ACR_USERNAME --password $ACR_PASSWORD

SERVICES=("product-api" "order-api" "payment-service" "notification-service")

for SERVICE in "${SERVICES[@]}"; do
    LOCAL_TAG="microservicesproject-${SERVICE}:latest"
    ACR_TAG="${ACR_LOGIN_SERVER}/${SERVICE}:latest"

    echo "      Tagging  ${LOCAL_TAG}  →  ${ACR_TAG}"
    docker tag $LOCAL_TAG $ACR_TAG

    echo "      Pushing  ${ACR_TAG}..."
    docker push $ACR_TAG
    if [ $? -ne 0 ]; then echo "ERROR: Push failed for ${SERVICE}"; exit 1; fi
    echo "      ✅ Pushed ${SERVICE}"
done

# ------------------------------------------------------------------
# STEP 5 — Create Container Apps Environment
# ------------------------------------------------------------------
echo ""
echo "[5/6] Ensuring Container Apps Environment '${ENVIRONMENT_NAME}' exists..."
az containerapp env create \
    --name $ENVIRONMENT_NAME \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --output none
echo "      Environment ready."

# ------------------------------------------------------------------
# STEP 6 — Deploy each service as a Container App
# ------------------------------------------------------------------
echo ""
echo "[6/6] Deploying Container Apps..."

# product-api — external (has Swagger UI)
echo ""
echo "      Deploying 'product-api'..."
az containerapp create \
    --name product-api \
    --resource-group $RESOURCE_GROUP \
    --environment $ENVIRONMENT_NAME \
    --image "${ACR_LOGIN_SERVER}/product-api:latest" \
    --registry-server $ACR_LOGIN_SERVER \
    --registry-username $ACR_USERNAME \
    --registry-password $ACR_PASSWORD \
    --target-port 8080 \
    --ingress external \
    --min-replicas 1 \
    --max-replicas 3 \
    --cpu 0.5 \
    --memory 1.0Gi \
    --env-vars "ConnectionStrings__DefaultConnection=${CONNECTION_STRING}" \
    --output none
echo "      ✅ Deployed product-api"

# order-api — external (has Swagger UI)
echo ""
echo "      Deploying 'order-api'..."
az containerapp create \
    --name order-api \
    --resource-group $RESOURCE_GROUP \
    --environment $ENVIRONMENT_NAME \
    --image "${ACR_LOGIN_SERVER}/order-api:latest" \
    --registry-server $ACR_LOGIN_SERVER \
    --registry-username $ACR_USERNAME \
    --registry-password $ACR_PASSWORD \
    --target-port 8080 \
    --ingress external \
    --min-replicas 1 \
    --max-replicas 3 \
    --cpu 0.5 \
    --memory 1.0Gi \
    --env-vars "ConnectionStrings__DefaultConnection=${CONNECTION_STRING}" \
    --output none
echo "      ✅ Deployed order-api"

# payment-service — internal worker (no ingress)
echo ""
echo "      Deploying 'payment-service'..."
az containerapp create \
    --name payment-service \
    --resource-group $RESOURCE_GROUP \
    --environment $ENVIRONMENT_NAME \
    --image "${ACR_LOGIN_SERVER}/payment-service:latest" \
    --registry-server $ACR_LOGIN_SERVER \
    --registry-username $ACR_USERNAME \
    --registry-password $ACR_PASSWORD \
    --min-replicas 1 \
    --max-replicas 3 \
    --cpu 0.5 \
    --memory 1.0Gi \
    --env-vars "ConnectionStrings__DefaultConnection=${CONNECTION_STRING}" \
    --output none
echo "      ✅ Deployed payment-service"

# notification-service — internal worker (no ingress)
echo ""
echo "      Deploying 'notification-service'..."
az containerapp create \
    --name notification-service \
    --resource-group $RESOURCE_GROUP \
    --environment $ENVIRONMENT_NAME \
    --image "${ACR_LOGIN_SERVER}/notification-service:latest" \
    --registry-server $ACR_LOGIN_SERVER \
    --registry-username $ACR_USERNAME \
    --registry-password $ACR_PASSWORD \
    --min-replicas 1 \
    --max-replicas 3 \
    --cpu 0.5 \
    --memory 1.0Gi \
    --env-vars "ConnectionStrings__DefaultConnection=${CONNECTION_STRING}" \
    --output none
echo "      ✅ Deployed notification-service"

# ------------------------------------------------------------------
# DONE — Print live URLs
# ------------------------------------------------------------------
echo ""
echo "============================================="
echo " Deployment Complete!"
echo "============================================="
echo ""
echo "Your public API URLs:"

PRODUCT_URL=$(az containerapp show \
    --name product-api \
    --resource-group $RESOURCE_GROUP \
    --query "properties.configuration.ingress.fqdn" \
    --output tsv)

ORDER_URL=$(az containerapp show \
    --name order-api \
    --resource-group $RESOURCE_GROUP \
    --query "properties.configuration.ingress.fqdn" \
    --output tsv)

echo "  Product API : https://${PRODUCT_URL}/swagger"
echo "  Order API   : https://${ORDER_URL}/swagger"
echo ""

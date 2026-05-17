# Microservices Project — .NET 8 + Docker + Azure

A production-ready microservices system built with .NET 8, containerised with Docker, and deployed to **Azure Container Apps** via **Azure Container Registry**.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                     Client / Swagger UI                  │
└──────────────┬──────────────────────┬───────────────────┘
               │                      │
       ┌───────▼──────┐      ┌────────▼──────┐
       │  product-api  │      │   order-api   │
       │  Port: 5001   │◄─────│  Port: 5002   │
       │  Web API      │      │  Web API      │
       └───────┬───────┘      └───────┬───────┘
               │                      │
               └──────────┬───────────┘
                          │
              ┌───────────▼───────────┐
              │     Azure SQL DB       │
              │     MicroservicesDb    │
              └───────────────────────┘
                          │
          ┌───────────────┴────────────────┐
          │                                │
  ┌───────▼────────┐            ┌──────────▼──────────┐
  │ payment-service│            │ notification-service │
  │ Worker Service │            │ Worker Service       │
  │ (background)   │            │ (background)         │
  └────────────────┘            └─────────────────────┘
```

---

## Services

| Service | Type | Port | Description |
|---|---|---|---|
| **product-api** | Web API | 5001 | Manages product catalogue — CRUD operations |
| **order-api** | Web API | 5002 | Handles order creation, calls product-api with Polly retry |
| **payment-service** | Worker | — | Background service, processes payments |
| **notification-service** | Worker | — | Background service, sends notifications |

---

## Tech Stack

| Layer | Technology |
|---|---|
| Language | C# / .NET 8 |
| API Framework | ASP.NET Core Minimal API |
| Background Services | .NET Worker Service |
| ORM | Entity Framework Core 8 |
| Database | Azure SQL (SQL Server) |
| Resilience | Polly v7 (retry + circuit breaker) |
| API Docs | Swagger / Swashbuckle |
| Containerisation | Docker + Docker Compose |
| Container Registry | Azure Container Registry (ACR) |
| Cloud Hosting | Azure Container Apps (ACA) |
| Deployment | PowerShell + Azure CLI |

---

## Project Structure

```
MicroservicesProject/
├── shared/
│   ├── SharedModels.csproj        # Shared class library
│   └── Models.cs                  # Domain models + DTOs used by all services
├── services/
│   ├── product-api/
│   │   ├── ProductApi.csproj
│   │   ├── Program.cs
│   │   ├── Dockerfile
│   │   └── appsettings.json
│   ├── order-api/
│   │   ├── OrderApi.csproj
│   │   ├── Program.cs
│   │   ├── Dockerfile
│   │   └── appsettings.json
│   ├── payment-service/
│   │   ├── PaymentService.csproj
│   │   ├── Program.cs
│   │   └── Dockerfile
│   └── notification-service/
│       ├── NotificationService.csproj
│       ├── Program.cs
│       └── Dockerfile
├── docker-compose.yaml            # Local development orchestration
├── deploy.ps1                     # Full Azure deployment script
├── .env.example                   # Environment variable template
├── .gitignore
└── MicroservicesProject.sln
```

---

## Getting Started — Run Locally

### Prerequisites
- [.NET 8 SDK](https://dotnet.microsoft.com/download)
- [Docker Desktop](https://www.docker.com/products/docker-desktop)
- [Azure SQL Database](https://azure.microsoft.com/en-us/products/azure-sql/database)

### Steps

**1. Clone the repository**
```bash
git clone https://github.com/YOUR_USERNAME/MicroservicesProject.git
cd MicroservicesProject
```

**2. Create your `.env` file**
```bash
cp .env.example .env
```
Open `.env` and fill in your Azure SQL password:
```
DB_PASSWORD=YourAzureSQLPassword
```

**3. Add your IP to Azure SQL firewall**
- Go to Azure Portal → SQL Server → Networking
- Add your client IP address
- Enable "Allow Azure services and resources to access this server"

**4. Build and run**
```bash
docker-compose up --build
```

**5. Open Swagger UI**
- Product API: http://localhost:5001/swagger
- Order API: http://localhost:5002/swagger

---

## Deploy to Azure

### Prerequisites
- [Azure CLI](https://aka.ms/installazurecliwindows)
- Active Azure subscription

### Steps

**1. Load your environment variables**
```powershell
Get-Content .env | ForEach-Object {
    if ($_ -match "^(.*?)=(.*)$") {
        [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2])
    }
}
```

**2. Run the deployment script**
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\deploy.ps1
```

The script will automatically:
- Build all 4 Docker images
- Create Azure Resource Group
- Create Azure Container Registry and push all images
- Create Container Apps Environment
- Deploy all 4 services as Container Apps

**3. Access your live APIs**

After deployment the script prints your public URLs:
```
Product API : https://product-api.xxx.azurecontainerapps.io/swagger
Order API   : https://order-api.xxx.azurecontainerapps.io/swagger
```

---

## API Endpoints

### Product API (port 5001)

| Method | Endpoint | Description |
|---|---|---|
| GET | `/products` | Get all products |
| GET | `/products/{id}` | Get product by ID |
| POST | `/products` | Create a new product |

### Order API (port 5002)

| Method | Endpoint | Description |
|---|---|---|
| POST | `/orders` | Create a new order |

---

## Key Design Decisions

**Shared models library** — All domain models and DTOs live in one shared project referenced by all services. This ensures type consistency across service boundaries without code duplication.

**Polly resilience** — order-api uses Polly to retry failed HTTP calls to product-api up to 3 times with exponential backoff (1s → 2s → 4s). This makes the system resilient to transient network failures.

**Multi-stage Dockerfiles** — Each Dockerfile uses a two-stage build. The SDK image compiles the code; the smaller runtime image runs it. This keeps final image sizes lean.

**Environment variable injection** — Database passwords are never hardcoded. They flow from `.env` → docker-compose → container at runtime, keeping secrets out of source control entirely.

**Non-fatal DB initialisation** — Services catch database connection errors at startup and log a warning instead of crashing. This means Swagger loads and the API is usable even if the database is temporarily unreachable.

---

## Environment Variables

| Variable | Description | Example |
|---|---|---|
| `DB_PASSWORD` | Azure SQL Server admin password | `MyPassword123!` |
| `ConnectionStrings__DefaultConnection` | Full connection string (injected by compose/ACA) | See docker-compose.yaml |

---

## License

MIT License — feel free to use this project as a reference or starting point.

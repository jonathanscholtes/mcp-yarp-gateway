# MCP_YARP_Proxy

## Overview

This repository contains the MCP YARP Proxy and related infrastructure, deployment scripts, and applications. It is designed to facilitate proxying, data seeding, and deployment of cloud and Kubernetes resources for MCP solutions.

## Project Structure

- `apps/`
  - `data-seeder/`: Python app for seeding data
  - `yarp-proxy/`: .NET YARP proxy application
- `infra/`: Bicep files for Azure infrastructure
- `k8s/helm/`: Helm charts for Kubernetes deployments
- `scripts/`: Deployment scripts (PowerShell, Python)

## Getting Started

### Prerequisites
- Azure subscription
- .NET 8 SDK
- Python 3.8+
- Docker
- Helm

### Setup
1. Clone the repository:
   ```sh
   git clone <repo-url>
   ```
2. Install dependencies for each app as needed.
3. Configure Azure credentials and required environment variables.

### Deployment

#### Infrastructure
- Deploy Azure resources using Bicep:
  ```sh
  ./scripts/Deploy-Infrastructure.ps1 -Subscription <subscription> -Location <location>
  ```

#### Kubernetes
- Deploy Helm charts:
  ```sh
  ./scripts/Deploy-Kubernetes.ps1
  ```

#### Foundry Agents
- Deploy Foundry agents:
  ```sh
  ./scripts/Deploy-FoundryAgents.ps1
  ```

#### Data Seeder
- Build and run the data seeder:
  ```sh
  cd apps/data-seeder
  python -m src.generator
  ```

#### YARP Proxy
- Build and run the proxy:
  ```sh
  cd apps/yarp-proxy
  dotnet build
  dotnet run
  ```

## Configuration

- Azure and Kubernetes configuration files are located in `infra/` and `k8s/helm/`.
- Application settings for YARP Proxy are in `apps/yarp-proxy/appsettings.json`.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## License

This project is licensed under the MIT License.

## Contact

For questions or support, contact the repository maintainer.

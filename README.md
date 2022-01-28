# Infrastructure as Code for an Elastic Search Cluster

This project will build out the Azure resources necessary for the deployment of Elastic Cloud Operator with instances of Grafana and Elastic Search with public https access points on Azure.

> **Note:** This project uses [VSCode Remote Containers](https://code.visualstudio.com/docs/remote/containers).

Set up your local environment variables

*Note: environment variables are automatically sourced by direnv after running (direnv allow)*

Required Environment Variables (.envrc)
```bash
# Azure Information
export ARM_TENANT_ID=""
export ARM_SUBSCRIPTION_ID=""

# Terraform-Principal Information
export ARM_CLIENT_ID=""
export ARM_CLIENT_SECRET=""
```


## Provisioned Resources

This deployment creates the following:

1. Azure Resource Group
2. Virtual Network with Network Security Groups and Route Table
3. Log Analtyics with Container Solution
4. Kubernetes Cluster (AKS) with User Managed Identity for Control Plane
5. Static IP Address for the Load Balancer with DNS name in Node Resource Group

The following Software Components are installed in AKS

1. Jet Stack Certificate Manager
2. NGINX Ingress Controller
3. Elastic Cloud Kubernetes Operator
4. Elastic Search Cluster
5. Grafana


## Example Usage

> **Note** Prior to deploying modify if desired the naming patterns in modules/naming-rules/custom.json

1. Execute the following commands to provision resources.

```bash
# Initialize and download the terraform modules required
terraform init

# See what terraform will try to deploy without actually deploying
terraform plan

# Execute a deployment
terraform apply
```
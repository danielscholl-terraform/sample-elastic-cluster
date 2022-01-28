/*
.Synopsis
   Terraform Main Control
.DESCRIPTION
   This file holds the main control and resoures for an elastic search cluster.
*/

terraform {
  required_version = ">= 1.1.1"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.90.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "=3.1.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "=3.1.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "=2.7.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "=2.4.1"
    }
  }
}


#-------------------------------
# Providers
#-------------------------------
provider "azurerm" {
  features {}
}

provider "kubernetes" {
  host                   = module.kubernetes.kube_config.host
  username               = module.kubernetes.kube_config.username
  password               = module.kubernetes.kube_config.password
  client_certificate     = base64decode(module.kubernetes.kube_config.client_certificate)
  client_key             = base64decode(module.kubernetes.kube_config.client_key)
  cluster_ca_certificate = base64decode(module.kubernetes.kube_config.cluster_ca_certificate)
}

provider "helm" {
  alias = "aks"
  debug = true
  kubernetes {
    host                   = module.kubernetes.kube_config.host
    username               = module.kubernetes.kube_config.username
    password               = module.kubernetes.kube_config.password
    client_certificate     = base64decode(module.kubernetes.kube_config.client_certificate)
    client_key             = base64decode(module.kubernetes.kube_config.client_key)
    cluster_ca_certificate = base64decode(module.kubernetes.kube_config.cluster_ca_certificate)
  }
}


#-------------------------------
# Application Variables  (variables.tf)
#-------------------------------
variable "name" {
  description = "An identifier used to construct the names of all resources in this template."
  type        = string
}

variable "location" {
  description = "The Azure region where all resources in this template should be created."
  type        = string
}

variable "randomization_level" {
  description = "Number of additional random characters to include in resource names to insulate against unexpected resource name collisions."
  type        = number
  default     = 8
}

variable "agent_vm_count" {
  type    = string
  default = "3"
}

variable "agent_vm_max_count" {
  type    = string
  default = "5"
}

variable "agent_vm_size" {
  type    = string
  default = "Standard_B2ms"
}

variable "email_address" {
  type = string
}


#-------------------------------
# SSH Key
#-------------------------------
resource "tls_private_key" "key" {
  algorithm = "RSA"
}

resource "null_resource" "save-key" {
  triggers = {
    key = tls_private_key.key.private_key_pem
  }

  provisioner "local-exec" {
    command = <<EOF
      mkdir -p ${path.module}/.ssh
      echo "${tls_private_key.key.private_key_pem}" > ${path.module}/.ssh/id_rsa
      chmod 0600 ${path.module}/.ssh/id_rsa
    EOF
  }
}


#-------------------------------
# Custom Naming Modules
#-------------------------------
module "naming" {
  source = "./modules/naming-rules"
}

module "metadata" {
  source = "./modules/metadata"

  naming_rules = module.naming.yaml

  location    = var.location
  product     = var.name
  environment = "sandbox"

  additional_tags = {
    "repo"  = "https://github.com/danielscholl-terraform/sample-elastic-cluster"
    "owner" = "Infrastructure Team"
  }
}


#-------------------------------
# Resource Group
#-------------------------------
module "resource_group" {
  source = "git::https://github.com/danielscholl-terraform/module-resource-group?ref=v1.0.0"

  names         = module.metadata.names
  location      = module.metadata.location
  resource_tags = module.metadata.tags
}


#-------------------------------
# Virtual Network
#-------------------------------
module "network" {
  source     = "git::https://github.com/danielscholl-terraform/module-virtual-network?ref=v1.0.0"
  depends_on = [module.resource_group]

  names               = module.metadata.names
  resource_group_name = module.resource_group.name
  resource_tags       = module.metadata.tags
  naming_rules        = module.naming.yaml

  dns_servers   = ["8.8.8.8"]
  address_space = ["10.1.0.0/22"]

  enforce_subnet_names = true

  subnets = {
    iaas-private = {
      cidrs                   = ["10.1.0.0/24"]
      route_table_association = "aks"
      configure_nsg_rules     = false
    }
    iaas-public = {
      cidrs                   = ["10.1.1.0/24"]
      route_table_association = "aks"
      configure_nsg_rules     = false
    }
  }

  route_tables = {
    aks = {
      disable_bgp_route_propagation = true
      use_inline_routes             = false
      routes = {
        internet = {
          address_prefix = "0.0.0.0/0"
          next_hop_type  = "Internet"
        }
        local-vnet = {
          address_prefix = "10.1.0.0/24"
          next_hop_type  = "vnetlocal"
        }
      }
    }
  }
}


#-------------------------------
# Log Analytics
#-------------------------------
module "log_analytics" {
  source     = "git::https://github.com/danielscholl-terraform/module-log-analytics?ref=v1.0.0"
  depends_on = [module.resource_group]

  naming_rules = module.naming.yaml

  names               = module.metadata.names
  resource_group_name = module.resource_group.name
  resource_tags       = module.metadata.tags

  solutions = [
    {
      solution_name = "ContainerInsights",
      publisher     = "Microsoft",
      product       = "OMSGallery/ContainerInsights",
    }
  ]
}


#-------------------------------
# Azure Kubernetes Service
#-------------------------------
module "kubernetes" {
  source     = "git::https://github.com/danielscholl-terraform/module-aks?ref=v1.0.0"
  depends_on = [module.resource_group, module.network, module.log_analytics]

  names               = module.metadata.names
  resource_group_name = module.resource_group.name
  node_resource_group = format("%s-cluster", module.resource_group.name)
  resource_tags       = module.metadata.tags

  enable_monitoring          = true
  log_analytics_workspace_id = module.log_analytics.id

  identity_type          = "UserAssigned"
  dns_prefix             = format("elastic-cluster-%s", module.resource_group.random)
  network_plugin         = "azure"
  network_policy         = "azure"
  configure_network_role = true

  virtual_network = {
    subnets = {
      iaas-private = {
        id = module.network.subnets["iaas-private"].id
      }
      iaas-public = {
        id = module.network.subnets["iaas-public"].id
      }
    }
    route_table_id = module.network.route_tables["aks"].id
  }

  linux_profile = {
    admin_username = "k8sadmin"
    ssh_key        = "${trimspace(tls_private_key.key.public_key_openssh)} k8sadmin"
  }
  default_node_pool = "default"
  node_pools = {
    default = {
      vm_size                      = "Standard_B2s"
      enable_host_encryption       = true
      only_critical_addons_enabled = true
      node_count                   = 3
      subnet                       = "iaas-private"
    }
    "${module.metadata.names.product}" = {
      vm_size                = var.agent_vm_size
      enable_host_encryption = true
      node_count             = var.agent_vm_count
      subnet                 = "iaas-public"
      enable_auto_scaling    = true
      min_count              = var.agent_vm_count
      max_count              = var.agent_vm_max_count
      node_labels = {
        "agentpool" = module.metadata.names.product
      }
    }
  }
}


#-------------------------------
# Certificate Manager
#-------------------------------
module "certificate_manager" {
  source     = "git::https://github.com/danielscholl-terraform/module-cert-manager?ref=v1.0.0"
  depends_on = [module.kubernetes]

  providers = { helm = helm.aks }

  name                        = format("%s-%s", module.metadata.names.product, module.resource_group.random)
  namespace                   = "cert-manager"
  kubernetes_create_namespace = true

  additional_yaml_config = yamlencode({ "nodeSelector" : { "agentpool" : module.metadata.names.product } })

  issuers = {
    staging = {
      namespace            = "cert-manager"
      cluster_issuer       = true
      email_address        = var.email_address
      letsencrypt_endpoint = "staging"
    }
    production = {
      namespace            = "cert-manager"
      cluster_issuer       = true
      email_address        = var.email_address
      letsencrypt_endpoint = "production"
    }
  }
}


#-------------------------------
# NGINX Ingress
#-------------------------------
# Create a Static IP Address
resource "azurerm_public_ip" "main" {
  name                = format("%s-ingress-ip", module.resource_group.name)
  resource_group_name = module.kubernetes.node_resource_group
  location            = module.resource_group.location
  allocation_method   = "Static"

  sku = "Standard"

  tags = {
    iac = "terraform"
  }

  lifecycle {
    ignore_changes = [
      domain_name_label,
      fqdn,
      tags
    ]
  }
}

# Open NSG Port http
resource "azurerm_network_security_rule" "ingress_public_allow_nginx_80" {
  name                        = "AllowNginx80"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "Internet"
  destination_address_prefix  = azurerm_public_ip.main.ip_address
  resource_group_name         = module.resource_group.name
  network_security_group_name = module.network.subnet_nsg_names["iaas-public"]
}

# Open NSG Port https
resource "azurerm_network_security_rule" "ingress_public_allow_nginx_443" {
  name                        = "AllowNginx443"
  priority                    = 101
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "Internet"
  destination_address_prefix  = azurerm_public_ip.main.ip_address
  resource_group_name         = module.resource_group.name
  network_security_group_name = module.network.subnet_nsg_names["iaas-public"]
}

# Deploy Nginx Ingress Controller
module "nginx_ingress" {
  source     = "git::https://github.com/danielscholl-terraform/module-nginx-ingress?ref=v1.0.0"
  depends_on = [module.kubernetes, module.certificate_manager]

  providers = { helm = helm.aks }

  name                        = "ingress-nginx"
  namespace                   = "nginx-system"
  kubernetes_create_namespace = true

  additional_yaml_config = yamlencode({ "nodeSelector" : { "agentpool" : module.metadata.names.product } })

  load_balancer_ip = azurerm_public_ip.main.ip_address
  dns_label        = format("%s-%s", module.metadata.names.product, module.resource_group.random)
}


#-------------------------------
# Elastic Cloud
#-------------------------------
module "elastic_cloud" {
  source     = "git::https://github.com/danielscholl-terraform/module-elastic-cloud?ref=main"
  depends_on = [module.kubernetes, module.certificate_manager, module.nginx_ingress]

  providers = { helm = helm.aks }

  name                        = "elastic-operator"
  namespace                   = "elastic-system"
  kubernetes_create_namespace = true
  additional_yaml_config      = yamlencode({ "nodeSelector" : { "agentpool" : module.metadata.names.product } })

  # Elastic Search Instances
  elasticsearch = {
    elastic-instance : {
      agent_pool = module.metadata.names.product
      node_count = 3
      storage    = 128
      cpu        = 2
      memory     = 8
      ingress    = true
      domain     = format("%s-%s.%s.cloudapp.azure.com", module.metadata.names.product, module.resource_group.random, module.resource_group.location)
    }
  }
}


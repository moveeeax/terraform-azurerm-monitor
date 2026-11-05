terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0, < 6.0"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "storage_account_id" {
  description = "ID of an existing storage account to monitor in the example."
  type        = string
}

module "monitor" {
  source = "../.."

  name                = "example-ag"
  resource_group_name = "example-rg"
  short_name          = "exampleag"

  email_receivers = {
    "oncall" = {
      email_address = "oncall@example.com"
    }
  }

  metric_alerts = {
    "high-transactions" = {
      description      = "Alert when transaction count is high."
      scopes           = [var.storage_account_id]
      metric_namespace = "Microsoft.Storage/storageAccounts"
      metric_name      = "Transactions"
      aggregation      = "Total"
      operator         = "GreaterThan"
      threshold        = 1000
    }
  }

  tags = {
    Environment = "sandbox"
    ManagedBy   = "terraform"
  }
}

output "action_group_id" {
  value = module.monitor.action_group_id
}

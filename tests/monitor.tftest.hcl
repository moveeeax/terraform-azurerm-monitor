# Test-only requirement: `mock_provider` needs Terraform >= 1.7 / OpenTofu >= 1.7.
# The module itself still supports the required_version declared in versions.tf.
mock_provider "azurerm" {
  # OpenTofu materialises mock values during plan, and azurerm validates that
  # action.action_group_id parses as an Azure resource ID - a random mock string
  # does not. Pin a well-formed ID so the suite behaves the same on both engines.
  mock_resource "azurerm_monitor_action_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Insights/actionGroups/test-ag"
    }
  }
}

variables {
  name                = "test-ag"
  resource_group_name = "test-rg"
  short_name          = "testag"

  email_receivers = {
    oncall = { email_address = "oncall@example.com" }
  }

  metric_alerts = {
    "cpu-high" = {
      scopes           = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Compute/virtualMachines/vm1"]
      metric_namespace = "Microsoft.Compute/virtualMachines"
      metric_name      = "Percentage CPU"
      aggregation      = "Average"
      operator         = "GreaterThan"
      threshold        = 80
    }
  }
}

run "defaults_are_safe" {
  command = plan

  assert {
    condition     = azurerm_monitor_metric_alert.this["cpu-high"].severity == 3
    error_message = "Metric alerts should default to severity 3."
  }

  assert {
    condition     = azurerm_monitor_metric_alert.this["cpu-high"].frequency == "PT1M"
    error_message = "Metric alerts should default to a PT1M evaluation frequency."
  }

  assert {
    condition     = azurerm_monitor_metric_alert.this["cpu-high"].window_size == "PT5M"
    error_message = "Metric alerts should default to a PT5M window."
  }

  assert {
    condition     = length(azurerm_monitor_metric_alert.this["cpu-high"].action) == 1
    error_message = "Every metric alert must be wired to exactly one action group, otherwise it notifies nobody."
  }

  assert {
    condition     = one(azurerm_monitor_action_group.this.email_receiver).use_common_alert_schema
    error_message = "Email receivers should default to the common alert schema."
  }
}

# The dominant failure mode for this module: alerts configured, nobody paged.
run "rejects_alerts_with_no_receivers" {
  command = plan

  variables {
    email_receivers = {}
  }

  expect_failures = [azurerm_monitor_metric_alert.this]
}

# An action group with no alerts is legitimate - the module must not force
# receivers on someone who only wants the action group.
run "action_group_only_is_allowed" {
  command = plan

  variables {
    email_receivers = {}
    metric_alerts   = {}
  }

  assert {
    condition     = azurerm_monitor_action_group.this.short_name == "testag"
    error_message = "The action group should still be creatable on its own."
  }
}

run "rejects_frequency_longer_than_window" {
  command = plan

  variables {
    metric_alerts = {
      "cpu-high" = {
        scopes           = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Compute/virtualMachines/vm1"]
        frequency        = "PT30M"
        window_size      = "PT5M"
        metric_namespace = "Microsoft.Compute/virtualMachines"
        metric_name      = "Percentage CPU"
        aggregation      = "Average"
        operator         = "GreaterThan"
        threshold        = 80
      }
    }
  }

  expect_failures = [var.metric_alerts]
}

run "rejects_invalid_severity" {
  command = plan

  variables {
    metric_alerts = {
      "cpu-high" = {
        scopes           = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Compute/virtualMachines/vm1"]
        severity         = 5
        metric_namespace = "Microsoft.Compute/virtualMachines"
        metric_name      = "Percentage CPU"
        aggregation      = "Average"
        operator         = "GreaterThan"
        threshold        = 80
      }
    }
  }

  expect_failures = [var.metric_alerts]
}

run "rejects_invalid_operator" {
  command = plan

  variables {
    metric_alerts = {
      "cpu-high" = {
        scopes           = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Compute/virtualMachines/vm1"]
        metric_namespace = "Microsoft.Compute/virtualMachines"
        metric_name      = "Percentage CPU"
        aggregation      = "Average"
        operator         = "MoreThan"
        threshold        = 80
      }
    }
  }

  expect_failures = [var.metric_alerts]
}

run "rejects_empty_scopes" {
  command = plan

  variables {
    metric_alerts = {
      "cpu-high" = {
        scopes           = []
        metric_namespace = "Microsoft.Compute/virtualMachines"
        metric_name      = "Percentage CPU"
        aggregation      = "Average"
        operator         = "GreaterThan"
        threshold        = 80
      }
    }
  }

  expect_failures = [var.metric_alerts]
}

# Azure requires target_resource_type/location for multi-resource and for
# subscription- or resource-group-scoped alerts.
run "rejects_multi_scope_without_target_resource" {
  command = plan

  variables {
    metric_alerts = {
      "cpu-high" = {
        scopes = [
          "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Compute/virtualMachines/vm1",
          "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Compute/virtualMachines/vm2",
        ]
        metric_namespace = "Microsoft.Compute/virtualMachines"
        metric_name      = "Percentage CPU"
        aggregation      = "Average"
        operator         = "GreaterThan"
        threshold        = 80
      }
    }
  }

  expect_failures = [var.metric_alerts]
}

run "accepts_multi_scope_with_target_resource" {
  command = plan

  variables {
    metric_alerts = {
      "cpu-high" = {
        scopes = [
          "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Compute/virtualMachines/vm1",
          "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Compute/virtualMachines/vm2",
        ]
        target_resource_type     = "Microsoft.Compute/virtualMachines"
        target_resource_location = "westeurope"
        metric_namespace         = "Microsoft.Compute/virtualMachines"
        metric_name              = "Percentage CPU"
        aggregation              = "Average"
        operator                 = "GreaterThan"
        threshold                = 80
      }
    }
  }

  assert {
    condition     = azurerm_monitor_metric_alert.this["cpu-high"].target_resource_location == "westeurope"
    error_message = "target_resource_location should be passed through to the alert."
  }
}

run "rejects_malformed_receiver_address" {
  command = plan

  variables {
    email_receivers = {
      oncall = { email_address = "oncall-at-example.com" }
    }
  }

  expect_failures = [var.email_receivers]
}

run "rejects_overlong_short_name" {
  command = plan

  variables {
    short_name = "waytoolongshortname"
  }

  expect_failures = [var.short_name]
}

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

  assert {
    condition = (
      length(azurerm_monitor_action_group.this.webhook_receiver) == 0
      && length(azurerm_monitor_action_group.this.sms_receiver) == 0
      && length(azurerm_monitor_action_group.this.azure_app_push_receiver) == 0
      && length(azurerm_monitor_action_group.this.logic_app_receiver) == 0
      && length(azurerm_monitor_action_group.this.arm_role_receiver) == 0
    )
    error_message = "No receiver types other than email may be added by default, so existing action groups plan unchanged."
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

# On-call setups usually page through a webhook or SMS, not email. A webhook on
# its own must satisfy the "alerts need a receiver" precondition.
run "webhook_only_receiver_satisfies_alerting" {
  command = plan

  variables {
    email_receivers = {}
    webhook_receivers = {
      pagerduty = { service_uri = "https://events.pagerduty.com/integration/0000/enqueue" }
    }
  }

  assert {
    condition     = one(azurerm_monitor_action_group.this.webhook_receiver).service_uri == "https://events.pagerduty.com/integration/0000/enqueue"
    error_message = "webhook_receivers service_uri should be passed through."
  }

  assert {
    condition     = one(azurerm_monitor_action_group.this.webhook_receiver).use_common_alert_schema
    error_message = "Webhook receivers should default to the common alert schema."
  }

  assert {
    condition     = length(one(azurerm_monitor_action_group.this.webhook_receiver).aad_auth) == 0
    error_message = "aad_auth should be omitted unless requested."
  }
}

run "all_receiver_types_are_wired" {
  command = plan

  variables {
    webhook_receivers = {
      secure-hook = {
        service_uri             = "https://hooks.example.com/azure"
        use_common_alert_schema = false
        aad_auth = {
          object_id = "11111111-1111-1111-1111-111111111111"
          tenant_id = "22222222-2222-2222-2222-222222222222"
        }
      }
    }
    sms_receivers = {
      oncall-sms = { country_code = "1", phone_number = "5551234567" }
    }
    azure_app_push_receivers = {
      oncall-push = { email_address = "oncall@example.com" }
    }
    logic_app_receivers = {
      teams = {
        resource_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Logic/workflows/teams-relay"
        callback_url = "https://prod-00.westeurope.logic.azure.com/workflows/0000/triggers/manual/paths/invoke?sig=redacted"
      }
    }
    arm_role_receivers = {
      owners = { role_id = "8e3af657-a8ff-443c-a75c-2fe8c4bcb635" }
    }
  }

  assert {
    condition     = one(one(azurerm_monitor_action_group.this.webhook_receiver).aad_auth).object_id == "11111111-1111-1111-1111-111111111111"
    error_message = "webhook aad_auth should be passed through."
  }

  assert {
    condition     = one(azurerm_monitor_action_group.this.webhook_receiver).use_common_alert_schema == false
    error_message = "An explicit use_common_alert_schema = false should be honoured."
  }

  assert {
    condition     = one(azurerm_monitor_action_group.this.sms_receiver).phone_number == "5551234567" && one(azurerm_monitor_action_group.this.sms_receiver).name == "oncall-sms"
    error_message = "sms_receivers should be passed through, named by their map key."
  }

  assert {
    condition     = one(azurerm_monitor_action_group.this.azure_app_push_receiver).email_address == "oncall@example.com"
    error_message = "azure_app_push_receivers should be passed through."
  }

  assert {
    condition     = one(azurerm_monitor_action_group.this.logic_app_receiver).resource_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Logic/workflows/teams-relay"
    error_message = "logic_app_receivers should be passed through."
  }

  assert {
    condition     = one(azurerm_monitor_action_group.this.arm_role_receiver).role_id == "8e3af657-a8ff-443c-a75c-2fe8c4bcb635"
    error_message = "arm_role_receivers should be passed through."
  }

  assert {
    condition     = length(azurerm_monitor_action_group.this.email_receiver) == 1
    error_message = "Adding other receiver types must not change the email receivers."
  }
}

run "rejects_plain_http_webhook" {
  command = plan

  variables {
    webhook_receivers = {
      hook = { service_uri = "http://hooks.example.com/azure" }
    }
  }

  expect_failures = [var.webhook_receivers]
}

run "rejects_webhook_aad_auth_without_uuid" {
  command = plan

  variables {
    webhook_receivers = {
      hook = {
        service_uri = "https://hooks.example.com/azure"
        aad_auth    = { object_id = "my-app" }
      }
    }
  }

  expect_failures = [var.webhook_receivers]
}

run "rejects_empty_sms_number" {
  command = plan

  variables {
    sms_receivers = {
      sms = { country_code = "1", phone_number = "" }
    }
  }

  expect_failures = [var.sms_receivers]
}

run "rejects_malformed_app_push_address" {
  command = plan

  variables {
    azure_app_push_receivers = {
      push = { email_address = "oncall" }
    }
  }

  expect_failures = [var.azure_app_push_receivers]
}

run "rejects_logic_app_resource_id_of_wrong_type" {
  command = plan

  variables {
    logic_app_receivers = {
      teams = {
        resource_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Web/sites/func"
        callback_url = "https://example.logic.azure.com/invoke"
      }
    }
  }

  expect_failures = [var.logic_app_receivers]
}

run "rejects_plain_http_logic_app_callback" {
  command = plan

  variables {
    logic_app_receivers = {
      teams = {
        resource_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Logic/workflows/teams-relay"
        callback_url = "http://example.logic.azure.com/invoke"
      }
    }
  }

  expect_failures = [var.logic_app_receivers]
}

run "rejects_arm_role_by_name" {
  command = plan

  variables {
    arm_role_receivers = {
      owners = { role_id = "Owner" }
    }
  }

  expect_failures = [var.arm_role_receivers]
}

run "rejects_receiver_names_clashing_across_types" {
  command = plan

  variables {
    webhook_receivers = {
      OnCall = { service_uri = "https://hooks.example.com/azure" }
    }
  }

  expect_failures = [azurerm_monitor_action_group.this]
}

locals {
  # Every receiver of every type, by name. Used to require at least one receiver
  # when alerts exist, and to enforce Azure's cross-type name uniqueness.
  receiver_names = concat(
    keys(var.email_receivers),
    keys(var.webhook_receivers),
    keys(var.sms_receivers),
    keys(var.azure_app_push_receivers),
    keys(var.logic_app_receivers),
    keys(var.arm_role_receivers),
  )
}

resource "azurerm_monitor_action_group" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  short_name          = var.short_name

  dynamic "email_receiver" {
    for_each = var.email_receivers
    content {
      name                    = email_receiver.key
      email_address           = email_receiver.value.email_address
      use_common_alert_schema = email_receiver.value.use_common_alert_schema
    }
  }

  dynamic "webhook_receiver" {
    for_each = var.webhook_receivers
    content {
      name                    = webhook_receiver.key
      service_uri             = webhook_receiver.value.service_uri
      use_common_alert_schema = webhook_receiver.value.use_common_alert_schema

      # Secure webhook: Azure Monitor obtains an Entra ID token for the given
      # application and sends it with each call.
      dynamic "aad_auth" {
        for_each = webhook_receiver.value.aad_auth == null ? [] : [webhook_receiver.value.aad_auth]
        content {
          object_id      = aad_auth.value.object_id
          identifier_uri = aad_auth.value.identifier_uri
          tenant_id      = aad_auth.value.tenant_id
        }
      }
    }
  }

  dynamic "sms_receiver" {
    for_each = var.sms_receivers
    content {
      name         = sms_receiver.key
      country_code = sms_receiver.value.country_code
      phone_number = sms_receiver.value.phone_number
    }
  }

  dynamic "azure_app_push_receiver" {
    for_each = var.azure_app_push_receivers
    content {
      name          = azure_app_push_receiver.key
      email_address = azure_app_push_receiver.value.email_address
    }
  }

  dynamic "logic_app_receiver" {
    for_each = var.logic_app_receivers
    content {
      name                    = logic_app_receiver.key
      resource_id             = logic_app_receiver.value.resource_id
      callback_url            = logic_app_receiver.value.callback_url
      use_common_alert_schema = logic_app_receiver.value.use_common_alert_schema
    }
  }

  dynamic "arm_role_receiver" {
    for_each = var.arm_role_receivers
    content {
      name                    = arm_role_receiver.key
      role_id                 = arm_role_receiver.value.role_id
      use_common_alert_schema = arm_role_receiver.value.use_common_alert_schema
    }
  }

  tags = var.tags

  lifecycle {
    # Azure requires receiver names to be unique, ignoring case, across all
    # receiver types in one action group. Each map already has unique keys;
    # this catches a clash between maps (or keys differing only in case).
    precondition {
      condition     = length(local.receiver_names) == length(distinct([for n in local.receiver_names : lower(n)]))
      error_message = "Receiver names (the map keys of email_receivers, webhook_receivers, sms_receivers, azure_app_push_receivers, logic_app_receivers and arm_role_receivers) must be unique across all receiver types, ignoring case."
    }
  }
}

resource "azurerm_monitor_metric_alert" "this" {
  for_each = var.metric_alerts

  name                = each.key
  resource_group_name = var.resource_group_name
  scopes              = each.value.scopes
  description         = each.value.description
  severity            = each.value.severity
  frequency           = each.value.frequency
  window_size         = each.value.window_size

  # Required by Azure for multi-resource alerts and for subscription/resource-group
  # scoped alerts; null (and therefore omitted) for single-resource alerts.
  target_resource_type     = each.value.target_resource_type
  target_resource_location = each.value.target_resource_location

  criteria {
    metric_namespace = each.value.metric_namespace
    metric_name      = each.value.metric_name
    aggregation      = each.value.aggregation
    operator         = each.value.operator
    threshold        = each.value.threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }

  tags = var.tags

  lifecycle {
    # An action group with no receivers accepts the alert and notifies nobody:
    # the alert fires, an incident is raised in Azure Monitor, and no human hears
    # about it. Fail at plan time rather than shipping silent alerting.
    precondition {
      condition     = length(local.receiver_names) > 0
      error_message = "metric_alerts are defined but the action group has no receivers, so alerts would notify nobody. Add at least one entry to email_receivers, webhook_receivers, sms_receivers, azure_app_push_receivers, logic_app_receivers or arm_role_receivers."
    }
  }
}

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

  tags = var.tags
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
      condition     = length(var.email_receivers) > 0
      error_message = "metric_alerts are defined but the action group has no receivers, so alerts would notify nobody. Add at least one entry to email_receivers."
    }
  }
}

# terraform-azurerm-monitor

Terraform module that manages [Azure Monitor](https://azure.microsoft.com/products/monitor)
alerting. It creates an action group with email, webhook, SMS, Azure app push,
Logic App and Azure Resource Manager role receivers and, driven
by an input map, a set of metric alerts that notify that action group when a
metric crosses a threshold.

## Usage

```hcl
module "monitor" {
  source = "github.com/moveeeax/terraform-azurerm-monitor?ref=v1.0.0"

  name                = "prod-ag"
  resource_group_name = "prod-rg"
  short_name          = "prodag"

  email_receivers = {
    "oncall" = { email_address = "oncall@example.com" }
  }

  metric_alerts = {
    "cpu-high" = {
      scopes           = ["/subscriptions/xxxx/resourceGroups/prod-rg/providers/Microsoft.Compute/virtualMachines/vm1"]
      metric_namespace = "Microsoft.Compute/virtualMachines"
      metric_name      = "Percentage CPU"
      aggregation      = "Average"
      operator         = "GreaterThan"
      threshold        = 80
    }
  }

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

A runnable example lives in [`examples/basic`](examples/basic).

### Receivers

Each receiver type is a map keyed by receiver name. Names must be unique across
all types, ignoring case (an Azure rule the module checks at plan time). Any
receiver type satisfies the "alerts need a receiver" check.

```hcl
  webhook_receivers = {
    # PagerDuty, Opsgenie or any HTTPS endpoint. Common alert schema is on by default.
    "pagerduty" = { service_uri = var.pagerduty_events_url }

    # Secure webhook: Azure Monitor authenticates with an Entra ID application.
    "internal-hook" = {
      service_uri = "https://alerts.example.com/azure"
      aad_auth    = { object_id = "00000000-0000-0000-0000-000000000000" }
    }
  }

  sms_receivers = {
    "oncall-sms" = { country_code = "1", phone_number = "5551234567" }
  }

  azure_app_push_receivers = {
    "oncall-push" = { email_address = "oncall@example.com" }
  }

  # Microsoft Teams is reached through a Logic App whose HTTP trigger posts to
  # the channel; azurerm_monitor_action_group has no Teams receiver block.
  logic_app_receivers = {
    "teams" = {
      resource_id  = azurerm_logic_app_workflow.teams_relay.id
      callback_url = azurerm_logic_app_trigger_http_request.teams_relay.callback_url
    }
  }

  arm_role_receivers = {
    # Email every holder of the role on the alerted subscription.
    "owners" = { role_id = "8e3af657-a8ff-443c-a75c-2fe8c4bcb635" } # Owner
  }
```

Webhook `service_uri` and Logic App `callback_url` must be `https://`. Both
usually embed a credential (an integration key, a SAS signature), and both end
up in Terraform state in plain text, so pass them from a secret store and
protect the state backend.

### Alerts spanning more than one resource

Azure requires `target_resource_type` and `target_resource_location` whenever an
alert is not scoped to a single concrete resource — that is, when `scopes` holds
more than one entry, or when a scope is a subscription or resource group rather
than a resource ID. The module enforces this at plan time:

```hcl
metric_alerts = {
  "fleet-cpu-high" = {
    scopes = [
      "/subscriptions/xxxx/resourceGroups/prod-rg/providers/Microsoft.Compute/virtualMachines/vm1",
      "/subscriptions/xxxx/resourceGroups/prod-rg/providers/Microsoft.Compute/virtualMachines/vm2",
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
```

## Validation

The module refuses configurations that Azure would accept-then-ignore, or reject
only at apply time:

- **Alerts must be able to reach somebody.** If `metric_alerts` is non-empty,
  at least one receiver of any type must exist. An action group with no
  receivers happily accepts alerts and notifies nobody.
- Receiver names must be unique across all receiver types, ignoring case.
- `frequency` must not be longer than `window_size`, and both must be valid
  Azure durations (`frequency`: `PT1M`, `PT5M`, `PT15M`, `PT30M`, `PT1H`;
  `window_size`: those plus `PT6H`, `PT12H`, `P1D`).
- `severity` must be an integer `0`–`4`.
- `aggregation` must be one of `Average`, `Count`, `Minimum`, `Maximum`, `Total`.
- `operator` must be one of `Equals`, `GreaterThan`, `GreaterThanOrEqual`,
  `LessThan`, `LessThanOrEqual`.
- `scopes` must be non-empty, and multi-resource or subscription/resource-group
  scoped alerts must set `target_resource_type` and `target_resource_location`.
- Every `email_receivers` and `azure_app_push_receivers` entry must have a
  syntactically valid address.
- Webhook `service_uri` and Logic App `callback_url` must be `https://` URLs;
  `aad_auth.object_id` and `arm_role_receivers` `role_id` must be UUIDs; a Logic
  App `resource_id` must be a `Microsoft.Logic/workflows` ID; SMS `country_code`
  and `phone_number` must be non-empty.

An action group with no alerts and no receivers is still allowed — the
requirement only applies once alerts exist.

## Tests

`tests/monitor.tftest.hcl` runs against a mocked provider, so it needs no Azure
credentials and no network:

```sh
terraform test
```

The test files use `mock_provider`, which requires Terraform/OpenTofu >= 1.7.
That is a test-only requirement; the module itself still supports the version
declared in `versions.tf`.

## Requirements

| Name      | Version  |
|-----------|----------|
| terraform | >= 1.5   |
| azurerm   | >= 3.0, < 6.0 |

CI validates and tests the module against the 3.0.0 floor and the latest azurerm
5.x release; 6.x is excluded until it has been tested.

## Inputs

| Name                  | Description                                                            | Type          | Default | Required |
|-----------------------|------------------------------------------------------------------------|---------------|---------|:--------:|
| `name`                | Name of the monitor action group.                                      | `string`      | n/a     |   yes    |
| `resource_group_name` | Name of the resource group in which to create the monitor resources.   | `string`      | n/a     |   yes    |
| `short_name`          | Short name of the action group (max 12 chars).                         | `string`      | n/a     |   yes    |
| `email_receivers`     | Map of email receivers keyed by receiver name.                         | `map(object)` | `{}`    |    no    |
| `webhook_receivers`   | Map of webhook receivers keyed by receiver name.                       | `map(object)` | `{}`    |    no    |
| `sms_receivers`       | Map of SMS receivers keyed by receiver name.                           | `map(object)` | `{}`    |    no    |
| `azure_app_push_receivers` | Map of Azure mobile app push receivers keyed by receiver name.    | `map(object)` | `{}`    |    no    |
| `logic_app_receivers` | Map of Logic App receivers keyed by receiver name.                     | `map(object)` | `{}`    |    no    |
| `arm_role_receivers`  | Map of Azure Resource Manager role receivers keyed by receiver name.   | `map(object)` | `{}`    |    no    |
| `metric_alerts`       | Map of metric alerts keyed by alert name.                              | `map(object)` | `{}`    |    no    |
| `tags`                | Map of tags applied to the monitor resources.                          | `map(string)` | `{}`    |    no    |

At least one receiver of any type is required when `metric_alerts` is set.

### `metric_alerts` object

| Field                      | Type           | Default  | Required |
|----------------------------|----------------|----------|:--------:|
| `scopes`                   | `list(string)` | n/a      |   yes    |
| `metric_namespace`         | `string`       | n/a      |   yes    |
| `metric_name`              | `string`       | n/a      |   yes    |
| `aggregation`              | `string`       | n/a      |   yes    |
| `operator`                 | `string`       | n/a      |   yes    |
| `threshold`                | `number`       | n/a      |   yes    |
| `description`              | `string`       | `null`   |    no    |
| `severity`                 | `number`       | `3`      |    no    |
| `frequency`                | `string`       | `"PT1M"` |    no    |
| `window_size`              | `string`       | `"PT5M"` |    no    |
| `target_resource_type`     | `string`       | `null`   |  see above |
| `target_resource_location` | `string`       | `null`   |  see above |

### `email_receivers` object

| Field                     | Type     | Default | Required |
|---------------------------|----------|---------|:--------:|
| `email_address`           | `string` | n/a     |   yes    |
| `use_common_alert_schema` | `bool`   | `true`  |    no    |

### `webhook_receivers` object

| Field                     | Type     | Default | Required |
|---------------------------|----------|---------|:--------:|
| `service_uri`             | `string` | n/a     |   yes    |
| `use_common_alert_schema` | `bool`   | `true`  |    no    |
| `aad_auth`                | `object({ object_id = string, identifier_uri = optional(string), tenant_id = optional(string) })` | `null` | no |

### `sms_receivers` object

| Field          | Type     | Default | Required |
|----------------|----------|---------|:--------:|
| `country_code` | `string` | n/a     |   yes    |
| `phone_number` | `string` | n/a     |   yes    |

### `azure_app_push_receivers` object

| Field           | Type     | Default | Required |
|-----------------|----------|---------|:--------:|
| `email_address` | `string` | n/a     |   yes    |

### `logic_app_receivers` object

| Field                     | Type     | Default | Required |
|---------------------------|----------|---------|:--------:|
| `resource_id`             | `string` | n/a     |   yes    |
| `callback_url`            | `string` | n/a     |   yes    |
| `use_common_alert_schema` | `bool`   | `true`  |    no    |

### `arm_role_receivers` object

| Field                     | Type     | Default | Required |
|---------------------------|----------|---------|:--------:|
| `role_id`                 | `string` | n/a     |   yes    |
| `use_common_alert_schema` | `bool`   | `true`  |    no    |

## Outputs

| Name                | Description                                  |
|---------------------|----------------------------------------------|
| `action_group_id`   | ID of the monitor action group.              |
| `action_group_name` | Name of the monitor action group.            |
| `metric_alert_ids`  | Map of metric alert names to their IDs.      |

## License

[MIT](LICENSE)

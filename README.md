# terraform-azurerm-monitor

Terraform module that manages [Azure Monitor](https://azure.microsoft.com/products/monitor)
alerting. It creates an action group with optional email receivers and, driven
by an input map, a set of metric alerts that notify that action group when a
metric crosses a threshold.

## Usage

```hcl
module "monitor" {
  source = "github.com/moveeeax/terraform-azurerm-monitor"

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
  `email_receivers` must be too. An action group with no receivers happily
  accepts alerts and notifies nobody.
- `frequency` must not be longer than `window_size`, and both must be valid
  Azure durations (`frequency`: `PT1M`, `PT5M`, `PT15M`, `PT30M`, `PT1H`;
  `window_size`: those plus `PT6H`, `PT12H`, `P1D`).
- `severity` must be an integer `0`–`4`.
- `aggregation` must be one of `Average`, `Count`, `Minimum`, `Maximum`, `Total`.
- `operator` must be one of `Equals`, `GreaterThan`, `GreaterThanOrEqual`,
  `LessThan`, `LessThanOrEqual`.
- `scopes` must be non-empty, and multi-resource or subscription/resource-group
  scoped alerts must set `target_resource_type` and `target_resource_location`.
- Every `email_receivers` entry must have a syntactically valid address.

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
| azurerm   | >= 3.0   |

## Inputs

| Name                  | Description                                                            | Type          | Default | Required |
|-----------------------|------------------------------------------------------------------------|---------------|---------|:--------:|
| `name`                | Name of the monitor action group.                                      | `string`      | n/a     |   yes    |
| `resource_group_name` | Name of the resource group in which to create the monitor resources.   | `string`      | n/a     |   yes    |
| `short_name`          | Short name of the action group (max 12 chars).                         | `string`      | n/a     |   yes    |
| `email_receivers`     | Map of email receivers keyed by receiver name. Required when `metric_alerts` is set. | `map(object)` | `{}`    |    no    |
| `metric_alerts`       | Map of metric alerts keyed by alert name.                              | `map(object)` | `{}`    |    no    |
| `tags`                | Map of tags applied to the monitor resources.                          | `map(string)` | `{}`    |    no    |

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

## Outputs

| Name                | Description                                  |
|---------------------|----------------------------------------------|
| `action_group_id`   | ID of the monitor action group.              |
| `action_group_name` | Name of the monitor action group.            |
| `metric_alert_ids`  | Map of metric alert names to their IDs.      |

## License

[MIT](LICENSE)

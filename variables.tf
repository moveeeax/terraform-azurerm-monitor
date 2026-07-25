variable "name" {
  description = "Name of the monitor action group."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group in which to create the monitor resources."
  type        = string
}

variable "short_name" {
  description = "Short name of the action group, used as the sender in notifications. Maximum 12 characters."
  type        = string

  validation {
    condition     = length(var.short_name) >= 1 && length(var.short_name) <= 12
    error_message = "The short_name must be between 1 and 12 characters."
  }
}

variable "email_receivers" {
  description = "Map of email receivers for the action group, keyed by receiver name. At least one receiver is required whenever metric_alerts is non-empty, otherwise alerts fire and notify nobody."
  type = map(object({
    email_address           = string
    use_common_alert_schema = optional(bool, true)
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.email_receivers : can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", v.email_address))])
    error_message = "Every email_receivers entry must have a syntactically valid email_address."
  }
}

variable "metric_alerts" {
  description = <<-EOT
    Map of metric alerts to create, keyed by alert name. Each alert targets the given scopes
    and fires the action group.

    `target_resource_type` and `target_resource_location` are required by Azure whenever the
    alert is not scoped to a single concrete resource - that is, when `scopes` holds more than
    one entry, or when a scope is a subscription or resource group rather than a resource ID.
  EOT
  type = map(object({
    description              = optional(string, null)
    scopes                   = list(string)
    severity                 = optional(number, 3)
    frequency                = optional(string, "PT1M")
    window_size              = optional(string, "PT5M")
    target_resource_type     = optional(string, null)
    target_resource_location = optional(string, null)
    metric_namespace         = string
    metric_name              = string
    aggregation              = string
    operator                 = string
    threshold                = number
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.metric_alerts : length(v.scopes) > 0])
    error_message = "Every metric alert must declare at least one entry in scopes; an alert with no scope evaluates nothing."
  }

  validation {
    condition     = alltrue([for k, v in var.metric_alerts : v.severity >= 0 && v.severity <= 4 && floor(v.severity) == v.severity])
    error_message = "Metric alert severity must be an integer between 0 (critical) and 4 (verbose)."
  }

  validation {
    condition     = alltrue([for k, v in var.metric_alerts : contains(["PT1M", "PT5M", "PT15M", "PT30M", "PT1H"], v.frequency)])
    error_message = "Metric alert frequency must be one of PT1M, PT5M, PT15M, PT30M, PT1H."
  }

  validation {
    condition     = alltrue([for k, v in var.metric_alerts : contains(["PT1M", "PT5M", "PT15M", "PT30M", "PT1H", "PT6H", "PT12H", "P1D"], v.window_size)])
    error_message = "Metric alert window_size must be one of PT1M, PT5M, PT15M, PT30M, PT1H, PT6H, PT12H, P1D."
  }

  validation {
    condition = alltrue([
      for k, v in var.metric_alerts :
      lookup({ "PT1M" = 60, "PT5M" = 300, "PT15M" = 900, "PT30M" = 1800, "PT1H" = 3600 }, v.frequency, 0) <=
      lookup({ "PT1M" = 60, "PT5M" = 300, "PT15M" = 900, "PT30M" = 1800, "PT1H" = 3600, "PT6H" = 21600, "PT12H" = 43200, "P1D" = 86400 }, v.window_size, 0)
    ])
    error_message = "Metric alert frequency must not be longer than window_size; Azure rejects the alert at apply time otherwise."
  }

  validation {
    condition     = alltrue([for k, v in var.metric_alerts : contains(["Average", "Count", "Minimum", "Maximum", "Total"], v.aggregation)])
    error_message = "Metric alert aggregation must be one of Average, Count, Minimum, Maximum, Total."
  }

  validation {
    condition     = alltrue([for k, v in var.metric_alerts : contains(["Equals", "GreaterThan", "GreaterThanOrEqual", "LessThan", "LessThanOrEqual"], v.operator)])
    error_message = "Metric alert operator must be one of Equals, GreaterThan, GreaterThanOrEqual, LessThan, LessThanOrEqual."
  }

  validation {
    condition = alltrue([
      for k, v in var.metric_alerts :
      v.target_resource_type != null && v.target_resource_location != null
      if length(v.scopes) > 1 || !alltrue([for s in v.scopes : strcontains(s, "/providers/")])
    ])
    error_message = "Metric alerts spanning multiple scopes, or scoped to a subscription or resource group, must set both target_resource_type and target_resource_location."
  }
}

variable "tags" {
  description = "Map of tags applied to the monitor resources."
  type        = map(string)
  default     = {}
}

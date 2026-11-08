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
  description = "Map of email receivers for the action group, keyed by receiver name. At least one receiver of any type is required whenever metric_alerts is non-empty, otherwise alerts fire and notify nobody."
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

variable "webhook_receivers" {
  description = <<-EOT
    Map of webhook receivers keyed by receiver name, e.g. a PagerDuty or Opsgenie
    integration URL. service_uri must be https. Set aad_auth to make it a secure
    webhook that authenticates with an Entra ID application. The URI is stored in
    state in plain text, so treat integration keys embedded in it as secrets.
  EOT
  type = map(object({
    service_uri             = string
    use_common_alert_schema = optional(bool, true)
    aad_auth = optional(object({
      object_id      = string
      identifier_uri = optional(string)
      tenant_id      = optional(string)
    }))
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.webhook_receivers : can(regex("^https://[^[:space:]]+$", v.service_uri))])
    error_message = "Every webhook_receivers service_uri must be an https:// URL. Alert payloads and any key embedded in the URL would otherwise travel in clear text."
  }

  validation {
    condition     = alltrue([for k, v in var.webhook_receivers : v.aad_auth == null ? true : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", v.aad_auth.object_id))])
    error_message = "webhook_receivers aad_auth.object_id must be a ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ (the object ID of the webhook's Entra ID application)."
  }
}

variable "sms_receivers" {
  description = "Map of SMS receivers keyed by receiver name. country_code is the international calling code (e.g. \"1\") and phone_number the number within it (e.g. \"5551234567\")."
  type = map(object({
    country_code = string
    phone_number = string
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.sms_receivers : length(trimspace(v.country_code)) > 0 && length(trimspace(v.phone_number)) > 0])
    error_message = "Every sms_receivers entry must have a non-empty country_code and phone_number."
  }
}

variable "azure_app_push_receivers" {
  description = "Map of Azure mobile app push receivers keyed by receiver name. email_address is the account the user signed in to the Azure app with."
  type = map(object({
    email_address = string
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.azure_app_push_receivers : can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", v.email_address))])
    error_message = "Every azure_app_push_receivers entry must have a syntactically valid email_address."
  }
}

variable "logic_app_receivers" {
  description = "Map of Logic App receivers keyed by receiver name, e.g. a workflow that posts to Microsoft Teams. callback_url is the workflow's HTTP trigger URL and must be https; it carries a SAS signature, so treat it as a secret (it is stored in state)."
  type = map(object({
    resource_id             = string
    callback_url            = string
    use_common_alert_schema = optional(bool, true)
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.logic_app_receivers : can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Logic/workflows/[^/]+$", v.resource_id))])
    error_message = "Every logic_app_receivers resource_id must be a Logic App workflow ID: /subscriptions/<id>/resourceGroups/<rg>/providers/Microsoft.Logic/workflows/<name>."
  }

  validation {
    condition     = alltrue([for k, v in var.logic_app_receivers : can(regex("^https://[^[:space:]]+$", v.callback_url))])
    error_message = "Every logic_app_receivers callback_url must be an https:// URL."
  }
}

variable "arm_role_receivers" {
  description = "Map of Azure Resource Manager role receivers keyed by receiver name. Members of the role (role_id is the role definition GUID, e.g. Owner or Monitoring Contributor) on the alerted subscription are notified by email."
  type = map(object({
    role_id                 = string
    use_common_alert_schema = optional(bool, true)
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.arm_role_receivers : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", v.role_id))])
    error_message = "Every arm_role_receivers role_id must be a role definition GUID, e.g. 8e3af657-a8ff-443c-a75c-2fe8c4bcb635 (Owner)."
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

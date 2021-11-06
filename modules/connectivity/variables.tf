# The following variables are used to determine the archetype
# definition to use and create the required resources.
#
# Further information provided within the description block
# for each variable

variable "enabled" {
  type        = bool
  description = "Controls whether to manage the connectivity landing zone policies and deploy the connectivity resources into the current Subscription context."
}

variable "root_id" {
  type        = string
  description = "Specifies the ID of the Enterprise-scale root Management Group, used as a prefix for resources created by this module."

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{2,10}$", var.root_id))
    error_message = "Value must be between 2 to 10 characters long, consisting of alphanumeric characters and hyphens."
  }
}

variable "subscription_id" {
  type        = string
  description = "Specifies the Subscription ID for the Subscription containing all connectivity resources."

  validation {
    condition     = can(regex("^[a-z0-9-]{36}$", var.subscription_id)) || var.subscription_id == ""
    error_message = "Value must be a valid Subscription ID (GUID)."
  }
}

variable "location" {
  type        = string
  description = "Sets the default location used for resource deployments where needed."
  default     = "eastus"
}

variable "tags" {
  type        = map(string)
  description = "If specified, will set the default tags for all resources deployed by this module where supported."
  default     = {}
}

variable "settings" {
  type = object({
    hub_networks = list(
      object({
        enabled = bool
        config = object({
          address_space                = list(string)
          location                     = string
          link_to_ddos_protection_plan = bool
          dns_servers                  = list(string)
          bgp_community                = string
          subnets = list(
            object({
              name                      = string
              address_prefixes          = list(string)
              network_security_group_id = string
              route_table_id            = string

              enforce_private_link_endpoint_network_policies = optional(bool)
              enforce_private_link_service_network_policies  = optional(bool)
              service_endpoints                              = optional(list(string))
              service_endpoint_policy_ids                    = optional(list(string))
              delegation                                     = optional(list(string))
            })
          )

          virtual_network_gateway = object({
            enabled = bool
            config = object({
              address_prefix           = string
              gateway_sku_expressroute = string
              gateway_sku_vpn          = string

              name                                           = optional(string)
              enforce_private_link_endpoint_network_policies = optional(bool)
              enforce_private_link_service_network_policies  = optional(bool)
              service_endpoints                              = optional(list(string))
              service_endpoint_policy_ids                    = optional(list(string))
              delegation                                     = optional(list(string))
              vpn_type                                       = optional(string)
              enable_bgp                                     = optional(bool)
              active_active                                  = optional(bool)
              private_ip_address_enabled                     = optional(bool)
              default_local_network_gateway_id               = optional(string)
              generation                                     = optional(string)
              vpn_client_configuration                       = optional(list(string))
              bgp_settings                                   = optional(list(string))
              custom_route                                   = optional(list(string))
              tags                                           = optional(map(string))

              public_ip_sku                     = optional(string)
              public_ip_allocation_method       = optional(string)
              public_ip_availability_zone       = optional(string)
              public_ip_ip_version              = optional(string)
              public_ip_idle_timeout_in_minutes = optional(string)
              public_ip_domain_name_label       = optional(string)
              public_ip_reverse_fqdn            = optional(string)
              public_ip_public_ip_prefix_id     = optional(string)
              public_ip_ip_tags                 = optional(map(string))
              public_ip_tags                    = optional(map(string))

              expressroute_vpn_type                         = optional(string)
              expressroute_enable_bgp                       = optional(bool)
              expressroute_active_active                    = optional(bool)
              expressroute_private_ip_address_enabled       = optional(bool)
              expressroute_default_local_network_gateway_id = optional(string)
              expressroute_generation                       = optional(string)
              expressroute_vpn_client_configuration         = optional(list(string))
              expressroute_bgp_settings                     = optional(list(string))
              expressroute_custom_route                     = optional(list(string))
              expressroute_tags                             = optional(map(string))

              expressroute_public_ip_sku                     = optional(string)
              expressroute_public_ip_allocation_method       = optional(string)
              expressroute_public_ip_availability_zone       = optional(string)
              expressroute_public_ip_ip_version              = optional(string)
              expressroute_public_ip_idle_timeout_in_minutes = optional(string)
              expressroute_public_ip_domain_name_label       = optional(string)
              expressroute_public_ip_reverse_fqdn            = optional(string)
              expressroute_public_ip_public_ip_prefix_id     = optional(string)
              expressroute_public_ip_ip_tags                 = optional(map(string))
              expressroute_public_ip_tags                    = optional(map(string))
            })
          })
          azure_firewall = object({
            enabled = bool
            config = object({
              address_prefix   = string
              enable_dns_proxy = bool
              availability_zones = object({
                zone_1 = bool
                zone_2 = bool
                zone_3 = bool
              })

              name                        = optional(string)
              sku_name                    = optional(string)
              sku_tier                    = optional(string)
              firewall_policy_id          = optional(string)
              dns_servers                 = optional(list(string))
              private_ip_ranges           = optional(list(string))
              management_ip_configuration = optional(list(string))
              threat_intel_mode           = optional(string)
              virtual_hub                 = optional(list(string))
              zones                       = optional(list(string))
              tags                        = optional(map(string))

              enforce_private_link_endpoint_network_policies = optional(bool)
              enforce_private_link_service_network_policies  = optional(bool)
              service_endpoints                              = optional(list(string))
              service_endpoint_policy_ids                    = optional(list(string))
              delegation                                     = optional(list(string))

              public_ip_sku                     = optional(string)
              public_ip_allocation_method       = optional(string)
              public_ip_ip_version              = optional(string)
              public_ip_idle_timeout_in_minutes = optional(string)
              public_ip_domain_name_label       = optional(string)
              public_ip_reverse_fqdn            = optional(string)
              public_ip_public_ip_prefix_id     = optional(string)
              public_ip_ip_tags                 = optional(map(string))
              public_ip_tags                    = optional(map(string))
            })
          })
          spoke_virtual_network_resource_ids      = list(string)
          enable_outbound_virtual_network_peering = bool

          virtual_network_name = optional(string)
          resource_group_name  = optional(string)
          resource_group_tags  = optional(map(string))
          tags                 = optional(map(string))
        })
      })
    )
    vwan_hub_networks = list(object({}))
    ddos_protection_plan = object({
      enabled = bool
      config = object({
        location            = string
        tags                = optional(map(string))
        name                = optional(string)
        resource_group_name = optional(string)
        resource_group_tags = optional(map(string))
      })
    })
    dns = object({
      enabled = bool
      config = object({
        location = string
        enable_private_link_by_service = object({
          azure_automation_webhook             = bool
          azure_automation_dscandhybridworker  = bool
          azure_sql_database_sqlserver         = bool
          azure_synapse_analytics_sqlserver    = bool
          azure_synapse_analytics_sql          = bool
          storage_account_blob                 = bool
          storage_account_table                = bool
          storage_account_queue                = bool
          storage_account_file                 = bool
          storage_account_web                  = bool
          azure_data_lake_file_system_gen2     = bool
          azure_cosmos_db_sql                  = bool
          azure_cosmos_db_mongodb              = bool
          azure_cosmos_db_cassandra            = bool
          azure_cosmos_db_gremlin              = bool
          azure_cosmos_db_table                = bool
          azure_database_for_postgresql_server = bool
          azure_database_for_mysql_server      = bool
          azure_database_for_mariadb_server    = bool
          azure_key_vault                      = bool
          azure_kubernetes_service_management  = bool
          azure_search_service                 = bool
          azure_container_registry             = bool
          azure_app_configuration_stores       = bool
          azure_backup                         = bool
          azure_site_recovery                  = bool
          azure_event_hubs_namespace           = bool
          azure_service_bus_namespace          = bool
          azure_iot_hub                        = bool
          azure_relay_namespace                = bool
          azure_event_grid_topic               = bool
          azure_event_grid_domain              = bool
          azure_web_apps_sites                 = bool
          azure_machine_learning_workspace     = bool
          signalr                              = bool
          azure_monitor                        = bool
          cognitive_services_account           = bool
          azure_file_sync                      = bool
          azure_data_factory                   = bool
          azure_data_factory_portal            = bool
          azure_cache_for_redis                = bool
        })
        private_link_locations                                 = list(string)
        public_dns_zones                                       = list(string)
        private_dns_zones                                      = list(string)
        enable_private_dns_zone_virtual_network_link_on_hubs   = bool
        enable_private_dns_zone_virtual_network_link_on_spokes = bool

        resource_group_name = optional(string)
        resource_group_tags = optional(map(string))

        fqdn = optional(map(object({
          resource_group_name = optional(string)
          soa_record          = optional(list(string))
          tags                = optional(map(string))
        })))
      })
    })
  })
}

variable "resource_prefix" {
  type        = string
  description = "If specified, will set the resource name prefix for connectivity resources (default value determined from \"var.root_id\")."
  default     = ""

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{2,10}$", var.resource_prefix)) || var.resource_prefix == ""
    error_message = "Value must be between 2 to 10 characters long, consisting of alphanumeric characters and hyphens."
  }
}

variable "resource_suffix" {
  type        = string
  description = "If specified, will set the resource name suffix for connectivity resources."
  default     = ""

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{2,36}$", var.resource_suffix)) || var.resource_suffix == ""
    error_message = "Value must be between 2 to 36 characters long, consisting of alphanumeric characters and hyphens."
  }

}

variable "existing_ddos_protection_plan_resource_id" {
  type        = string
  description = "If specified, module will skip creation of DDoS Protection Plan and use existing."
  default     = ""
}

variable "custom_settings_by_resource_type" {
  type        = any
  description = "If specified, allows full customization of common settings for all resources (by type) deployed by this module."
  default     = {}

  validation {
    condition     = can([for k in keys(var.custom_settings_by_resource_type) : contains(["azurerm_resource_group", "azurerm_virtual_network", "azurerm_subnet", "azurerm_virtual_network_gateway", "azurerm_public_ip", "azurerm_firewall", "azurerm_network_ddos_protection_plan", "azurerm_dns_zone", "azurerm_virtual_network_peering"], k)]) || var.custom_settings_by_resource_type == {}
    error_message = "Invalid key specified. Please check the list of allowed resource types supported by the connectivity module for caf-enterprise-scale."
  }
}

# The following block of locals are used to avoid using
# empty object types in the code.
locals {
  empty_list   = []
  empty_map    = {}
  empty_string = ""
}

# Convert the input vars to locals, applying any required
# logic needed before they are used in the module.
# No vars should be referenced elsewhere in the module.
# NOTE: Need to catch error for resource_suffix when
# no value for subscription_id is provided.
locals {
  enabled                                   = var.enabled
  root_id                                   = var.root_id
  subscription_id                           = coalesce(var.subscription_id, "00000000-0000-0000-0000-000000000000")
  settings                                  = var.settings
  location                                  = var.location
  tags                                      = var.tags
  resource_prefix                           = coalesce(var.resource_prefix, local.root_id)
  resource_suffix                           = length(var.resource_suffix) > 0 ? "-${var.resource_suffix}" : local.empty_string
  existing_ddos_protection_plan_resource_id = var.existing_ddos_protection_plan_resource_id
  custom_settings                           = var.custom_settings_by_resource_type
}

# Logic to help keep code DRY
locals {
  hub_networks = local.settings.hub_networks
  # We generate the hub_networks_by_location as a map
  # to ensure the user has provided unique values for
  # each hub location. If duplicates are found,
  # terraform will throw an error at this point.
  hub_networks_by_location = {
    for hub_network in local.hub_networks :
    coalesce(hub_network.config.location, local.location) => hub_network
  }
  hub_network_locations = keys(local.hub_networks_by_location)
  ddos_location         = coalesce(local.settings.ddos_protection_plan.config.location, local.location)
  dns_location          = coalesce(local.settings.dns.config.location, local.location)
}


# Logic to determine whether specific resources
# should be created by this module
locals {
  deploy_ddos_protection_plan = local.enabled && local.settings.ddos_protection_plan.enabled
  deploy_dns                  = local.enabled && local.settings.dns.enabled
  deploy_resource_groups = {
    connectivity = {
      for location, hub_network in local.hub_networks_by_location :
      location =>
      local.enabled &&
      hub_network.enabled
    }
    ddos = {
      (local.ddos_location) = local.deploy_ddos_protection_plan
    }
    dns = {
      (local.dns_location) = local.deploy_dns
    }
  }
  deploy_hub_network = {
    for location, hub_network in local.hub_networks_by_location :
    location =>
    local.enabled &&
    hub_network.enabled
  }
  deploy_virtual_network_gateway = {
    for location, hub_network in local.hub_networks_by_location :
    location =>
    local.deploy_hub_network[location] &&
    hub_network.config.virtual_network_gateway.enabled &&
    hub_network.config.virtual_network_gateway.config.address_prefix != local.empty_string
  }
  deploy_virtual_network_gateway_expressroute = {
    for location, hub_network in local.hub_networks_by_location :
    location =>
    local.deploy_virtual_network_gateway[location] &&
    hub_network.config.virtual_network_gateway.config.gateway_sku_expressroute != local.empty_string
  }
  deploy_virtual_network_gateway_vpn = {
    for location, hub_network in local.hub_networks_by_location :
    location =>
    local.deploy_virtual_network_gateway[location] &&
    hub_network.config.virtual_network_gateway.config.gateway_sku_vpn != local.empty_string
  }
  deploy_azure_firewall = {
    for location, hub_network in local.hub_networks_by_location :
    location =>
    local.deploy_hub_network[location] &&
    hub_network.config.azure_firewall.enabled
  }
  deploy_outbound_virtual_network_peering = {
    for location, hub_network in local.hub_networks_by_location :
    location =>
    local.deploy_dns &&
    hub_network.config.enable_outbound_virtual_network_peering
  }
  deploy_private_dns_zone_virtual_network_link_on_hubs   = local.deploy_dns && local.settings.dns.config.enable_private_dns_zone_virtual_network_link_on_hubs
  deploy_private_dns_zone_virtual_network_link_on_spokes = local.deploy_dns && local.settings.dns.config.enable_private_dns_zone_virtual_network_link_on_spokes
}


# Configuration settings for resource type:
#  - azurerm_resource_group
locals {
  # Determine the name of each Resource Group per scope and location
  resource_group_names_by_scope_and_location_p1 = {
    connectivity = {
      for location, hub in local.hub_networks_by_location :
      location =>
      {
        name = coalesce(hub.config.resource_group_name, "${local.resource_prefix}-connectivity-${location}${local.resource_suffix}")
        tags = coalesce(hub.config.resource_group_tags, local.tags)
      }
    }
    ddos = {
      (local.ddos_location) = {
        name = coalesce(local.settings.ddos_protection_plan.config.resource_group_name, "${local.resource_prefix}-ddos${local.resource_suffix}")
        tags = coalesce(local.settings.ddos_protection_plan.config.resource_group_tags, local.tags)
      }
    }
    dns = {
      (local.dns_location) = {
        name = coalesce(local.settings.dns.config.resource_group_name, "${local.resource_prefix}-dns${local.resource_suffix}")
        tags = coalesce(local.settings.dns.config.resource_group_tags, local.tags)
      }
    }
  }
  resource_group_names_by_scope_and_location = {
    for scope, resource_groups in local.resource_group_names_by_scope_and_location_p1 :
    scope => {
      for location, rg in resource_groups :
      location => rg.name
    }
  }
  # Generate a map of settings for each Resource Group per scope and location
  resource_group_config_by_scope_and_location = {
    for scope, resource_groups in local.resource_group_names_by_scope_and_location_p1 :
    scope => {
      for location, rg in resource_groups :
      location => {
        # Resource logic attributes
        resource_id = "/subscriptions/${local.subscription_id}/resourceGroups/${rg.name}"
        scope       = scope
        # Resource definition attributes
        name     = rg.name
        location = location
        tags     = rg.tags
      }
    }
  }
  # Create a flattened list of resource group configuration blocks for deployment
  azurerm_resource_group = flatten([
    for scope in keys(local.resource_group_config_by_scope_and_location) :
    [
      for config in local.resource_group_config_by_scope_and_location[scope] :
      config
    ]
  ])
}

# # Configuration settings for resource type:
# #  - azurerm_network_ddos_protection_plan
locals {
  ddos_resource_group_id = local.resource_group_config_by_scope_and_location["ddos"][local.ddos_location].resource_id
  ddos_protection_plan_name = coalesce(local.settings.ddos_protection_plan.config.name,
  "${local.resource_prefix}-ddos-${local.ddos_location}${local.resource_suffix}")
  ddos_protection_plan_resource_id = coalesce(
    local.existing_ddos_protection_plan_resource_id,
    "${local.ddos_resource_group_id}/providers/Microsoft.Network/ddosProtectionPlans/${local.ddos_protection_plan_name}"
  )
  azurerm_network_ddos_protection_plan = [
    {
      # Resource logic attributes
      resource_id       = local.ddos_protection_plan_resource_id
      managed_by_module = local.deploy_ddos_protection_plan
      # Resource definition attributes
      name                = local.ddos_protection_plan_name
      location            = local.ddos_location
      resource_group_name = local.resource_group_config_by_scope_and_location["ddos"][local.ddos_location].name
      tags                = coalesce(local.settings.ddos_protection_plan.config.tags, local.tags)
    }
  ]
}

# Configuration settings for resource type:
#  - azurerm_virtual_network
locals {
  virtual_network_resource_group_id = {
    for location in local.hub_network_locations :
    location =>
    local.resource_group_config_by_scope_and_location["connectivity"][location].resource_id
  }
  azurerm_virtual_network = [for h in [
    for location, hub_config in local.hub_networks_by_location :
    {
      # Resource definition attributes
      name                = coalesce(hub_config.config.virtual_network_name, "${local.resource_prefix}-hub-${location}${local.resource_suffix}")
      resource_group_name = local.resource_group_names_by_scope_and_location["connectivity"][location]
      address_space       = hub_config.config.address_space
      location            = location
      bgp_community       = hub_config.config.bgp_community != local.empty_string ? hub_config.config.bgp_community : null
      dns_servers         = hub_config.config.dns_servers
      tags                = coalesce(hub_config.config.tags, local.tags)
      ddos_protection_plan = hub_config.config.link_to_ddos_protection_plan ? [
        {
          id     = local.ddos_protection_plan_resource_id
          enable = true
        }
      ] : local.empty_list
    }
    ] :
    merge(h,
      {
        # Resource logic attributes
        resource_id = "${local.virtual_network_resource_group_id[h.location]}/providers/Microsoft.Network/virtualNetworks/${h.name}"
      }
    )
  ]
  virtual_network_name = {
    for v in local.azurerm_virtual_network :
    v.location => v.name
  }
  virtual_network_resource_id = {
    for v in local.azurerm_virtual_network :
    v.location => v.resource_id
  }
}

# Configuration settings for resource type:
#  - azurerm_subnet
locals {
  subnets_by_virtual_network = {
    for location, hub_network in local.hub_networks_by_location :
    local.virtual_network_resource_id[location] => concat(
      # Get customer specified subnets and add additional required attributes
      [
        for subnet in hub_network.config.subnets : merge(
          subnet,
          {
            # Resource logic attributes
            resource_id = "${local.virtual_network_resource_id[location]}/subnets/${subnet.name}"
            location    = location
            # Resource definition attributes
            resource_group_name                            = local.resource_group_names_by_scope_and_location["connectivity"][location]
            virtual_network_name                           = local.virtual_network_name[location]
            enforce_private_link_endpoint_network_policies = subnet.enforce_private_link_endpoint_network_policies
            enforce_private_link_service_network_policies  = subnet.enforce_private_link_service_network_policies
            service_endpoints                              = subnet.service_endpoints
            service_endpoint_policy_ids                    = subnet.service_endpoint_policy_ids
            delegation                                     = coalesce(subnet.delegation, [])
          }
        )
      ],
      # Conditionally add Virtual Network Gateway subnet
      hub_network.config.virtual_network_gateway.config.address_prefix != local.empty_string ? [
        {
          # Resource logic attributes
          resource_id               = "${local.virtual_network_resource_id[location]}/subnets/GatewaySubnet"
          location                  = location
          network_security_group_id = null
          route_table_id            = null
          # Resource definition attributes
          name                                           = "GatewaySubnet"
          address_prefixes                               = [hub_network.config.virtual_network_gateway.config.address_prefix, ]
          resource_group_name                            = local.resource_group_names_by_scope_and_location["connectivity"][location]
          virtual_network_name                           = local.virtual_network_name[location]
          enforce_private_link_endpoint_network_policies = hub_network.config.virtual_network_gateway.config.enforce_private_link_endpoint_network_policies
          enforce_private_link_service_network_policies  = hub_network.config.virtual_network_gateway.config.enforce_private_link_service_network_policies
          service_endpoints                              = hub_network.config.virtual_network_gateway.config.service_endpoints
          service_endpoint_policy_ids                    = hub_network.config.virtual_network_gateway.config.service_endpoint_policy_ids
          delegation                                     = coalesce(hub_network.config.virtual_network_gateway.config.delegation, [])
        }
      ] : local.empty_list,
      # Conditionally add Azure Firewall subnet
      hub_network.config.azure_firewall.config.address_prefix != local.empty_string ? [
        {
          # Resource logic attributes
          resource_id               = "${local.virtual_network_resource_id[location]}/subnets/AzureFirewallSubnet"
          location                  = location
          network_security_group_id = null
          route_table_id            = null
          # Resource definition attributes
          name                                           = "AzureFirewallSubnet"
          address_prefixes                               = [hub_network.config.azure_firewall.config.address_prefix, ]
          resource_group_name                            = local.resource_group_names_by_scope_and_location["connectivity"][location]
          virtual_network_name                           = local.virtual_network_name[location]
          enforce_private_link_endpoint_network_policies = hub_network.config.azure_firewall.config.enforce_private_link_endpoint_network_policies
          enforce_private_link_service_network_policies  = hub_network.config.azure_firewall.config.enforce_private_link_service_network_policies
          service_endpoints                              = hub_network.config.azure_firewall.config.service_endpoints
          service_endpoint_policy_ids                    = hub_network.config.azure_firewall.config.service_endpoint_policy_ids
          delegation                                     = coalesce(hub_network.config.azure_firewall.config.delegation, [])
        }
      ] : local.empty_list,
    )
  }
  azurerm_subnet = flatten([
    for subnets in local.subnets_by_virtual_network :
    subnets
  ])
}

# Configuration settings for resource type:
#  - azurerm_virtual_network_gateway (ExpressRoute)
locals {


  er_gateway_name = {
    for location, hub_network in local.hub_networks_by_location :
    location => coalesce(hub_network.config.virtual_network_gateway.config.name, "${local.resource_prefix}-ergw-${location}${local.resource_suffix}")
  }

  er_gateway_config = [for g in [
    for location, hub_network in local.hub_networks_by_location :
    {
      # Resource logic attributes
      managed_by_module = local.deploy_virtual_network_gateway_expressroute[location]
      # Resource definition attributes
      name                = local.er_gateway_name[location]
      resource_group_name = local.resource_group_names_by_scope_and_location["connectivity"][location]
      location            = location
      type                = "ExpressRoute"
      sku                 = hub_network.config.virtual_network_gateway.config.gateway_sku_expressroute
      ip_configuration = coalesce(
        # To support `active_active = true` must currently specify a custom ip_configuration
        hub_network.config.virtual_network_gateway.config.expressroute_ip_configuration,
        [
          {
            name                          = coalesce(hub_network.config.virtual_network_gateway.config.expressroute_public_ip_name, "${local.er_gateway_name[location]}-pip")
            private_ip_address_allocation = null
            subnet_id                     = "${local.virtual_network_resource_id[location]}/subnets/GatewaySubnet"
            public_ip_address_id          = "${local.virtual_network_resource_group_id[location]}/providers/Microsoft.Network/publicIPAddresses/${coalesce(hub_network.config.virtual_network_gateway.config.expressroute_public_ip_name, "${local.er_gateway_name[location]}-pip")}"
          }
        ]
      )
      vpn_type                         = coalesce(hub_network.config.virtual_network_gateway.config.expressroute_vpn_type, "RouteBased")
      enable_bgp                       = coalesce(hub_network.config.virtual_network_gateway.config.expressroute_enable_bgp, true)
      active_active                    = coalesce(hub_network.config.virtual_network_gateway.config.expressroute_active_active, false)
      private_ip_address_enabled       = hub_network.config.virtual_network_gateway.config.expressroute_private_ip_address_enabled
      default_local_network_gateway_id = hub_network.config.virtual_network_gateway.config.expressroute_default_local_network_gateway_id
      generation                       = hub_network.config.virtual_network_gateway.config.expressroute_generation
      vpn_client_configuration         = coalesce(hub_network.config.virtual_network_gateway.config.expressroute_vpn_client_configuration, [])
      bgp_settings                     = coalesce(hub_network.config.virtual_network_gateway.config.expressroute_bgp_settings, [])
      custom_route                     = coalesce(hub_network.config.virtual_network_gateway.config.expressroute_custom_route, [])
      tags                             = coalesce(hub_network.config.virtual_network_gateway.config.expressroute_tags, local.tags)
      # Child resource definition attributes
      azurerm_public_ip = {
        # Resource logic attributes
        resource_id       = "${local.virtual_network_resource_group_id[location]}/providers/Microsoft.Network/publicIPAddresses/${coalesce(hub_network.config.virtual_network_gateway.config.expressroute_public_ip_name, "${local.er_gateway_name[location]}-pip")}"
        managed_by_module = local.deploy_virtual_network_gateway_expressroute[location]
        # Resource definition attributes
        name                    = coalesce(hub_network.config.virtual_network_gateway.config.expressroute_public_ip_name, "${local.er_gateway_name[location]}-pip")
        resource_group_name     = local.resource_group_names_by_scope_and_location["connectivity"][location]
        location                = location
        sku                     = coalesce(hub_network.config.virtual_network_gateway.config.expressroute_public_ip_sku, "Standard")
        ip_version              = hub_network.config.virtual_network_gateway.config.expressroute_public_ip_ip_version
        idle_timeout_in_minutes = hub_network.config.virtual_network_gateway.config.expressroute_public_ip_idle_timeout_in_minutes
        domain_name_label       = hub_network.config.virtual_network_gateway.config.expressroute_public_ip_domain_name_label
        reverse_fqdn            = hub_network.config.virtual_network_gateway.config.expressroute_public_ip_reverse_fqdn
        public_ip_prefix_id     = hub_network.config.virtual_network_gateway.config.expressroute_public_ip_public_ip_prefix_id
        ip_tags                 = hub_network.config.virtual_network_gateway.config.expressroute_public_ip_ip_tags
        tags                    = coalesce(hub_network.config.virtual_network_gateway.config.expressroute_public_ip_tags, local.tags)
        allocation_method = coalesce(
          hub_network.config.virtual_network_gateway.config.expressroute_public_ip_allocation_method,
          try(local.custom_settings.azurerm_public_ip["connectivity"]["ergw"][location].sku, "Standard") == "Standard" ? "Static" : "Dynamic"
        )
        availability_zone = coalesce(
          hub_network.config.virtual_network_gateway.config.expressroute_public_ip_availability_zone,
          length(regexall("AZ$", hub_network.config.virtual_network_gateway.config.gateway_sku_expressroute)) > 0 ? "Zone-Redundant" : "No-Zone"
        )
      }
    }
    ] : merge(g, {
      resource_id = "/subscriptions/${local.subscription_id}/${g.resource_group_name}/providers/Microsoft.Network/virtualNetworkGateways/${g.name}"
    })
  ]
  er_gateway_resource_id = {
    for g in local.er_gateway_config :
    g.location => g.resource_id
  }
}

# Configuration settings for resource type:
#  - azurerm_virtual_network_gateway (VPN)
locals {
  vpn_gateway_name = {
    for location, hub_network in local.hub_networks_by_location :
    location => coalesce(hub_network.config.virtual_network_gateway.config.name, "${local.resource_prefix}-vpngw-${location}${local.resource_suffix}")
  }

  vpn_gateway_config = [for g in [
    for location, hub_network in local.hub_networks_by_location :
    {
      # Resource logic attributes
      managed_by_module = local.deploy_virtual_network_gateway_vpn[location]
      # Resource definition attributes
      name                = local.vpn_gateway_name[location]
      resource_group_name = local.resource_group_names_by_scope_and_location["connectivity"][location]
      location            = location
      type                = "Vpn"
      sku                 = hub_network.config.virtual_network_gateway.config.gateway_sku_vpn
      ip_configuration = coalesce(
        # To support `active_active = true` must currently specify a custom ip_configuration
        hub_network.config.virtual_network_gateway.config.vpn_ip_configuration,
        [
          {
            name                          = coalesce(hub_network.config.virtual_network_gateway.config.vpn_public_ip_name, "${local.vpn_gateway_name[location]}-pip")
            private_ip_address_allocation = null
            subnet_id                     = "${local.virtual_network_resource_id[location]}/subnets/GatewaySubnet"
            public_ip_address_id          = "${local.virtual_network_resource_group_id[location]}/providers/Microsoft.Network/publicIPAddresses/${coalesce(hub_network.config.virtual_network_gateway.config.vpn_public_ip_name, "${local.vpn_gateway_name[location]}-pip")}"
          }
        ]
      )
      vpn_type                         = coalesce(hub_network.config.virtual_network_gateway.config.vpn_type, "RouteBased")
      enable_bgp                       = coalesce(hub_network.config.virtual_network_gateway.config.vpn_enable_bgp, false)
      active_active                    = coalesce(hub_network.config.virtual_network_gateway.config.vpn_active_active, false)
      private_ip_address_enabled       = hub_network.config.virtual_network_gateway.config.vpn_private_ip_address_enabled
      default_local_network_gateway_id = hub_network.config.virtual_network_gateway.config.vpn_default_local_network_gateway_id
      generation                       = hub_network.config.virtual_network_gateway.config.vpn_generation
      vpn_client_configuration         = coalesce(hub_network.config.virtual_network_gateway.config.vpn_client_configuration, [])
      bgp_settings                     = coalesce(hub_network.config.virtual_network_gateway.config.vpn_bgp_settings, [])
      custom_route                     = coalesce(hub_network.config.virtual_network_gateway.config.vpn_custom_route, [])
      tags                             = coalesce(hub_network.config.virtual_network_gateway.config.vpn_tags, local.tags)
      # Child resource definition attributes
      azurerm_public_ip = {
        # Resource logic attributes
        resource_id       = "${local.virtual_network_resource_group_id[location]}/providers/Microsoft.Network/publicIPAddresses/${coalesce(hub_network.config.virtual_network_gateway.config.vpn_public_ip_name, "${local.vpn_gateway_name[location]}-pip")}"
        managed_by_module = local.deploy_virtual_network_gateway_vpn[location]
        # Resource definition attributes
        name                    = coalesce(hub_network.config.virtual_network_gateway.config.vpn_public_ip_name, "${local.vpn_gateway_name[location]}-pip")
        resource_group_name     = local.resource_group_names_by_scope_and_location["connectivity"][location]
        location                = location
        ip_version              = hub_network.config.virtual_network_gateway.config.vpn_public_ip_ip_version
        idle_timeout_in_minutes = hub_network.config.virtual_network_gateway.config.vpn_public_ip_idle_timeout_in_minutes
        domain_name_label       = hub_network.config.virtual_network_gateway.config.vpn_public_ip_domain_name_label
        reverse_fqdn            = hub_network.config.virtual_network_gateway.config.vpn_public_ip_reverse_fqdn
        public_ip_prefix_id     = hub_network.config.virtual_network_gateway.config.vpn_public_ip_public_ip_prefix_id
        ip_tags                 = coalesce(hub_network.config.virtual_network_gateway.config.vpn_public_ip_ip_tags, {})
        tags                    = coalesce(hub_network.config.virtual_network_gateway.config.vpn_public_ip_tags, local.tags)
        sku = try(
          hub_network.config.virtual_network_gateway.config.vpn_public_ip_sku,
          length(regexall("AZ$", hub_network.config.virtual_network_gateway.config.gateway_sku_vpn)) > 0 ? "Standard" : "Basic"
        )
        allocation_method = try(
          hub_network.config.virtual_network_gateway.config.vpn_public_ip_allocation_method,
          length(regexall("AZ$", hub_network.config.virtual_network_gateway.config.gateway_sku_vpn)) > 0 ? "Static" : "Dynamic"
        )
        availability_zone = try(
          hub_network.config.virtual_network_gateway.config.vpn_public_ip_availability_zone,
          length(regexall("AZ$", hub_network.config.virtual_network_gateway.config.gateway_sku_vpn)) > 0 ? "Zone-Redundant" : "No-Zone"
        )
      }
    }
    ] : merge(g, {

      resource_id = "/subscriptions/${local.subscription_id}/${g.resource_group_name}/providers/Microsoft.Network/virtualNetworkGateways/${g.name}"
    })
  ]

  vpn_gateway_resource_id = {
    for vpn in local.vpn_gateway_config :
    vpn.location => vpn.resource_id
  }
}

# Configuration settings for resource type:
#  - azurerm_virtual_network_gateway
locals {
  azurerm_virtual_network_gateway = concat(
    local.er_gateway_config,
    local.vpn_gateway_config,
  )
}

# Configuration settings for resource type:
#  - azurerm_firewall
locals {

  azfw_zones = {
    for location, hub_network in local.hub_networks_by_location :
    location =>
    flatten(
      [
        hub_network.config.azure_firewall.config.availability_zones.zone_1 ? ["1"] : [],
        hub_network.config.azure_firewall.config.availability_zones.zone_2 ? ["2"] : [],
        hub_network.config.azure_firewall.config.availability_zones.zone_3 ? ["3"] : [],
      ]
    )
  }
  azfw_zones_enabled = {
    for location, hub_network in local.hub_networks_by_location :
    location =>
    length(local.azfw_zones[location]) > 0
  }

  azfw_name = {
    for location, hub_network in local.hub_networks_by_location :
    location => coalesce(hub_network.config.azure_firewall.config.name, "${local.resource_prefix}-fw-${location}${local.resource_suffix}")
  }

  azurerm_firewall = [for f in [
    for location, hub_network in local.hub_networks_by_location :
    {
      # Resource logic attributes
      managed_by_module = local.deploy_azure_firewall[location]
      # Resource definition attributes
      name                = local.azfw_name[location]
      resource_group_name = local.resource_group_names_by_scope_and_location["connectivity"][location]
      location            = hub_network.config.location

      sku_name                    = coalesce(hub_network.config.azure_firewall.config.sku_name, "AZFW_VNet")
      sku_tier                    = coalesce(hub_network.config.azure_firewall.config.sku_tier, "Standard")
      firewall_policy_id          = hub_network.config.azure_firewall.config.firewall_policy_id
      dns_servers                 = hub_network.config.azure_firewall.config.dns_servers
      private_ip_ranges           = hub_network.config.azure_firewall.config.private_ip_ranges
      management_ip_configuration = coalesce(hub_network.config.azure_firewall.config.management_ip_configuration, [])
      threat_intel_mode           = hub_network.config.azure_firewall.config.threat_intel_mode
      virtual_hub                 = coalesce(hub_network.config.azure_firewall.config.virtual_hub, [])
      zones                       = coalesce(hub_network.config.azure_firewall.config.zones, local.azfw_zones[location])
      tags                        = coalesce(hub_network.config.azure_firewall.config.tags, local.tags)
      # Child resource definition attributes
      ip_configuration = coalesce(
        hub_network.config.azure_firewall.config.ip_configuration,
        [
          {
            name                 = coalesce(hub_network.config.azure_firewall.config.public_ip_name, "${local.azfw_name[location]}-pip")
            public_ip_address_id = "${local.virtual_network_resource_group_id[location]}/providers/Microsoft.Network/publicIPAddresses/${coalesce(hub_network.config.azure_firewall.config.public_ip_name, "${local.azfw_name[location]}-pip")}"
            subnet_id            = "${local.virtual_network_resource_id[location]}/subnets/AzureFirewallSubnet"
          }
        ]
      )
      azurerm_public_ip = {
        # Resource logic attributes
        resource_id       = "${local.virtual_network_resource_group_id[location]}/providers/Microsoft.Network/publicIPAddresses/${coalesce(hub_network.config.azure_firewall.config.public_ip_name, "${local.azfw_name[location]}-pip")}"
        managed_by_module = local.deploy_azure_firewall[location]
        # Resource definition attributes
        name                    = coalesce(hub_network.config.azure_firewall.config.public_ip_name, "${local.azfw_name[location]}-pip")
        resource_group_name     = local.resource_group_names_by_scope_and_location["connectivity"][location]
        location                = location
        sku                     = coalesce(hub_network.config.azure_firewall.config.public_ip_sku, "Standard")
        allocation_method       = coalesce(hub_network.config.azure_firewall.config.public_ip_allocation_method, "Static")
        ip_version              = hub_network.config.azure_firewall.config.public_ip_ip_version
        idle_timeout_in_minutes = hub_network.config.azure_firewall.config.public_ip_idle_timeout_in_minutes
        domain_name_label       = hub_network.config.azure_firewall.config.public_ip_domain_name_label
        reverse_fqdn            = hub_network.config.azure_firewall.config.public_ip_reverse_fqdn
        public_ip_prefix_id     = hub_network.config.azure_firewall.config.public_ip_public_ip_prefix_id
        ip_tags                 = coalesce(hub_network.config.azure_firewall.config.public_ip_ip_tags, {})
        tags                    = coalesce(hub_network.config.azure_firewall.config.public_ip_tags, local.tags)
        availability_zone = coalesce(
          hub_network.config.azure_firewall.config.public_ip_availability_zone,
          local.azfw_zones_enabled[location] ? "Zone-Redundant" : "No-Zone"
        )
      }
    }
    ] : merge(f, {
      resource_id = "/subscriptions/${local.subscription_id}/${f.resource_group_name}/providers/Microsoft.Network/azureFirewalls/${f.name}"
    })
  ]

  azfw_resource_id = {
    for f in local.azurerm_firewall :
    f.location => f.resource_id
  }
}

# Configuration settings for resource type:
#  - azurerm_public_ip
locals {
  azurerm_public_ip = concat(
    local.azurerm_virtual_network_gateway.*.azurerm_public_ip,
    local.azurerm_firewall.*.azurerm_public_ip,
  )
}

# Configuration settings for resource type:
#  - azurerm_private_dns_zone
locals {
  enable_private_link_by_service = local.settings.dns.config.enable_private_link_by_service
  private_link_locations         = coalescelist(local.settings.dns.config.private_link_locations, [local.location])
  private_dns_zone_prefix        = "${local.resource_group_config_by_scope_and_location["dns"][local.dns_location].resource_id}/providers/Microsoft.Network/privateDnsZones/"
  lookup_private_link_dns_zone_by_service = {
    azure_automation_webhook             = ["privatelink.azure-automation.net"]
    azure_automation_dscandhybridworker  = ["privatelink.azure-automation.net"]
    azure_sql_database_sqlserver         = ["privatelink.database.windows.net"]
    azure_synapse_analytics_sqlserver    = ["privatelink.database.windows.net"]
    azure_synapse_analytics_sql          = ["privatelink.sql.azuresynapse.net"]
    storage_account_blob                 = ["privatelink.blob.core.windows.net"]
    storage_account_table                = ["privatelink.table.core.windows.net"]
    storage_account_queue                = ["privatelink.queue.core.windows.net"]
    storage_account_file                 = ["privatelink.file.core.windows.net"]
    storage_account_web                  = ["privatelink.web.core.windows.net"]
    azure_data_lake_file_system_gen2     = ["privatelink.dfs.core.windows.net"]
    azure_cosmos_db_sql                  = ["privatelink.documents.azure.com"]
    azure_cosmos_db_mongodb              = ["privatelink.mongo.cosmos.azure.com"]
    azure_cosmos_db_cassandra            = ["privatelink.cassandra.cosmos.azure.com"]
    azure_cosmos_db_gremlin              = ["privatelink.gremlin.cosmos.azure.com"]
    azure_cosmos_db_table                = ["privatelink.table.cosmos.azure.com"]
    azure_database_for_postgresql_server = ["privatelink.postgres.database.azure.com"]
    azure_database_for_mysql_server      = ["privatelink.mysql.database.azure.com"]
    azure_database_for_mariadb_server    = ["privatelink.mariadb.database.azure.com"]
    azure_key_vault                      = ["privatelink.vaultcore.azure.net"]
    azure_kubernetes_service_management = [
      for location in local.private_link_locations :
      "privatelink.${location}.azmk8s.io"
    ]
    azure_search_service           = ["privatelink.search.windows.net"]
    azure_container_registry       = ["privatelink.azurecr.io"]
    azure_app_configuration_stores = ["privatelink.azconfig.io"]
    azure_backup = [
      for location in local.private_link_locations :
      "privatelink.${location}.backup.windowsazure.com"
    ]
    azure_site_recovery = [
      for location in local.private_link_locations :
      "${location}.privatelink.siterecovery.windowsazure.com"
    ]
    azure_event_hubs_namespace       = ["privatelink.servicebus.windows.net"]
    azure_service_bus_namespace      = ["privatelink.servicebus.windows.net"]
    azure_iot_hub                    = ["privatelink.azure-devices.net", "privatelink.servicebus.windows.net"]
    azure_relay_namespace            = ["privatelink.servicebus.windows.net"]
    azure_event_grid_topic           = ["privatelink.eventgrid.azure.net"]
    azure_event_grid_domain          = ["privatelink.eventgrid.azure.net"]
    azure_web_apps_sites             = ["privatelink.azurewebsites.net"]
    azure_machine_learning_workspace = ["privatelink.api.azureml.ms", "privatelink.notebooks.azure.net"]
    signalr                          = ["privatelink.service.signalr.net"]
    azure_monitor                    = ["privatelink.monitor.azure.com", "privatelink.oms.opinsights.azure.com", "privatelink.ods.opinsights.azure.com", "privatelink.agentsvc.azure-automation.net"]
    cognitive_services_account       = ["privatelink.cognitiveservices.azure.com"]
    azure_file_sync                  = ["privatelink.afs.azure.net"]
    azure_data_factory               = ["privatelink.datafactory.azure.net"]
    azure_data_factory_portal        = ["privatelink.adf.azure.com"]
    azure_cache_for_redis            = ["privatelink.redis.cache.windows.net"]
  }
  lookup_private_link_group_id_by_service = {
    azure_automation_webhook             = ""
    azure_automation_dscandhybridworker  = ""
    azure_sql_database_sqlserver         = "sqlServer"
    azure_synapse_analytics_sqlserver    = ""
    azure_synapse_analytics_sql          = ""
    storage_account_blob                 = "blob"
    storage_account_table                = "table"
    storage_account_queue                = "queue"
    storage_account_file                 = "file"
    storage_account_web                  = "web"
    azure_data_lake_file_system_gen2     = "dfs"
    azure_cosmos_db_sql                  = ""
    azure_cosmos_db_mongodb              = ""
    azure_cosmos_db_cassandra            = ""
    azure_cosmos_db_gremlin              = ""
    azure_cosmos_db_table                = ""
    azure_database_for_postgresql_server = ""
    azure_database_for_mysql_server      = ""
    azure_database_for_mariadb_server    = ""
    azure_key_vault                      = "vault"
    azure_kubernetes_service_management  = ""
    azure_search_service                 = ""
    azure_container_registry             = ""
    azure_app_configuration_stores       = ""
    azure_backup                         = ""
    azure_site_recovery                  = ""
    azure_event_hubs_namespace           = ""
    azure_service_bus_namespace          = ""
    azure_iot_hub                        = ""
    azure_relay_namespace                = ""
    azure_event_grid_topic               = ""
    azure_event_grid_domain              = ""
    azure_web_apps_sites                 = ""
    azure_machine_learning_workspace     = ""
    signalr                              = ""
    azure_monitor                        = ""
    cognitive_services_account           = ""
    azure_file_sync                      = ""
    azure_data_factory                   = ""
    azure_data_factory_portal            = ""
    azure_cache_for_redis                = ""
  }
  services_by_private_link_dns_zone = transpose(local.lookup_private_link_dns_zone_by_service)
  private_dns_zone_enabled = {
    for fqdn, services in local.services_by_private_link_dns_zone :
    fqdn => anytrue(
      [
        for service in services : local.enable_private_link_by_service[service]
      ]
    )
  }
  azurerm_private_dns_zone = concat(
    [
      for fqdn, services in local.services_by_private_link_dns_zone :
      {
        # Resource logic attributes
        resource_id       = "${local.resource_group_config_by_scope_and_location["dns"][local.dns_location].resource_id}/providers/Microsoft.Network/privateDnsZones/${fqdn}"
        managed_by_module = local.deploy_dns && local.private_dns_zone_enabled[fqdn]
        # Resource definition attributes
        name = fqdn
        resource_group_name = try(
          local.settings.dns.config.fqdn[fqdn].resource_group_name,
          local.resource_group_names_by_scope_and_location["dns"][local.dns_location]
        )
        # Optional definition attributes
        soa_record = try(local.settings.dns.config.fqdn[fqdn].soa_record, [])
        tags       = try(local.settings.dns.config.fqdn[fqdn].tags, local.tags)
      }
    ],
    [
      for fqdn in local.settings.dns.config.private_dns_zones :
      {
        # Resource logic attributes
        resource_id       = "${local.resource_group_config_by_scope_and_location["dns"][local.dns_location].resource_id}/providers/Microsoft.Network/privateDnsZones/${fqdn}"
        managed_by_module = local.deploy_dns
        # Resource definition attributes
        name = fqdn
        resource_group_name = try(
          local.settings.dns.config.fqdn[fqdn].resource_group_name,
          local.resource_group_names_by_scope_and_location["dns"][local.dns_location]
        )
        # Optional definition attributes
        soa_record = try(local.settings.dns.config.fqdn[fqdn].soa_record, [])
        tags       = try(local.settings.dns.config.fqdn[fqdn].tags, local.tags)
      }
    ],
  )
}

# Configuration settings for resource type:
#  - azurerm_dns_zone
locals {
  azurerm_dns_zone = [
    for fqdn in local.settings.dns.config.public_dns_zones :
    {
      # Resource logic attributes
      resource_id       = "${local.resource_group_config_by_scope_and_location["dns"][local.dns_location].resource_id}/providers/Microsoft.Network/dnszones/${fqdn}"
      managed_by_module = local.deploy_dns
      # Resource definition attributes
      name = fqdn
      resource_group_name = try(
        local.settings.dns.config.fqdn[fqdn].resource_group_name,
        local.resource_group_names_by_scope_and_location["dns"][local.dns_location]
      )
      # Optional definition attributes
      soa_record = try(local.settings.dns.config.fqdn[fqdn].soa_record, [])
      tags       = try(local.settings.dns.config.fqdn[fqdn].tags, local.tags)
    }
  ]
}

# Configuration settings for resource type:
#  - azurerm_private_dns_zone_virtual_network_link
locals {
  hub_virtual_networks_for_dns = [
    for hub_config in local.azurerm_virtual_network :
    {
      resource_id       = hub_config.resource_id
      name              = "${split("/", hub_config.resource_id)[2]}-${uuidv5("url", hub_config.resource_id)}"
      managed_by_module = local.deploy_private_dns_zone_virtual_network_link_on_hubs
    }
  ]
  spoke_virtual_networks_for_dns = flatten(
    [
      for location, hub_config in local.hub_networks_by_location :
      [
        for spoke_resource_id in hub_config.config.spoke_virtual_network_resource_ids :
        {
          resource_id       = spoke_resource_id
          name              = "${split("/", spoke_resource_id)[2]}-${uuidv5("url", spoke_resource_id)}"
          managed_by_module = local.deploy_private_dns_zone_virtual_network_link_on_spokes
        }
      ]
    ]
  )
  virtual_networks_for_dns = concat(
    local.hub_virtual_networks_for_dns,
    local.spoke_virtual_networks_for_dns,
  )
  azurerm_private_dns_zone_virtual_network_link = flatten(
    [
      for zone in local.azurerm_private_dns_zone :
      [
        for link_config in local.virtual_networks_for_dns :
        {
          # Resource logic attributes
          resource_id       = "${zone.resource_id}/virtualNetworkLinks/${link_config.name}"
          managed_by_module = zone.managed_by_module
          # Resource definition attributes
          name                  = link_config.name
          resource_group_name   = zone.resource_group_name
          private_dns_zone_name = zone.name
          virtual_network_id    = link_config.resource_id
          # Optional definition attributes
          registration_enabled = try(local.custom_settings.azurerm_private_dns_zone_virtual_network_link["connectivity"][link_config.name][zone.name].registration_enabled, false)
          tags                 = try(local.custom_settings.azurerm_private_dns_zone_virtual_network_link["connectivity"][link_config.name]["global"].tags, local.tags)
        }
      ]
    ]
  )
}

# Configuration settings for resource type:
#  - azurerm_virtual_network_peering
locals {
  azurerm_virtual_network_peering = flatten(
    [
      for location, hub_config in local.hub_networks_by_location :
      [
        for spoke_resource_id in hub_config.config.spoke_virtual_network_resource_ids :
        {
          # Resource logic attributes
          resource_id       = "${local.virtual_network_resource_id[location]}/virtualNetworkPeerings/peering-${uuidv5("url", spoke_resource_id)}"
          managed_by_module = local.deploy_outbound_virtual_network_peering[location]
          # Resource definition attributes
          name                      = "peering-${uuidv5("url", spoke_resource_id)}"
          resource_group_name       = local.resource_group_names_by_scope_and_location["connectivity"][location]
          virtual_network_name      = local.virtual_network_name[location]
          remote_virtual_network_id = spoke_resource_id
          # Optional definition attributes
          allow_virtual_network_access = true
          allow_forwarded_traffic      = true
          allow_gateway_transit        = true
          use_remote_gateways          = false
        }
      ]
    ]
  )
}

# Archetype configuration overrides
locals {
  archetype_config_overrides = {
    "${local.root_id}-connectivity" = {
      parameters = {
        Enable-DDoS-VNET = {
          ddosPlan = local.ddos_protection_plan_resource_id
        }
      }
      enforcement_mode = {
        Enable-DDoS-VNET = local.deploy_ddos_protection_plan
      }
    }
    "${local.root_id}-corp" = {
      parameters = {
        Deploy-Private-DNS-Zones = {
          azureFilePrivateDnsZoneId                     = "${local.private_dns_zone_prefix}privatelink.afs.azure.net"
          azureWebPrivateDnsZoneId                      = "${local.private_dns_zone_prefix}privatelink.webpubsub.azure.com"
          azureBatchPrivateDnsZoneId                    = "${local.private_dns_zone_prefix}privatelink.${local.location}.batch.azure.com"
          azureAppPrivateDnsZoneId                      = "${local.private_dns_zone_prefix}privatelink.azconfig.io"
          azureAsrPrivateDnsZoneId                      = "${local.private_dns_zone_prefix}privatelink.siterecovery.windowsazure.com"
          azureIoTPrivateDnsZoneId                      = "${local.private_dns_zone_prefix}privatelink.azure-devices-provisioning.net"
          azureKeyVaultPrivateDnsZoneId                 = "${local.private_dns_zone_prefix}privatelink.vaultcore.azure.net"
          azureSignalRPrivateDnsZoneId                  = "${local.private_dns_zone_prefix}privatelink.service.signalr.net"
          azureAppServicesPrivateDnsZoneId              = "${local.private_dns_zone_prefix}privatelink.azurewebsites.net"
          azureEventGridTopicsPrivateDnsZoneId          = "${local.private_dns_zone_prefix}privatelink.eventgrid.azure.net"
          azureDiskAccessPrivateDnsZoneId               = "${local.private_dns_zone_prefix}privatelink.blob.core.windows.net"
          azureCognitiveServicesPrivateDnsZoneId        = "${local.private_dns_zone_prefix}privatelink.cognitiveservices.azure.com"
          azureIotHubsPrivateDnsZoneId                  = "${local.private_dns_zone_prefix}privatelink.azure-devices.net"
          azureEventGridDomainsPrivateDnsZoneId         = "${local.private_dns_zone_prefix}privatelink.eventgrid.azure.net"
          azureRedisCachePrivateDnsZoneId               = "${local.private_dns_zone_prefix}privatelink.redis.cache.windows.net"
          azureAcrPrivateDnsZoneId                      = "${local.private_dns_zone_prefix}privatelink.azurecr.io"
          azureEventHubNamespacePrivateDnsZoneId        = "${local.private_dns_zone_prefix}privatelink.servicebus.windows.net"
          azureMachineLearningWorkspacePrivateDnsZoneId = "${local.private_dns_zone_prefix}privatelink.api.azureml.ms"
          azureServiceBusNamespacePrivateDnsZoneId      = "${local.private_dns_zone_prefix}privatelink.servicebus.windows.net"
          azureCognitiveSearchPrivateDnsZoneId          = "${local.private_dns_zone_prefix}privatelink.search.windows.net"
        }
      }
      enforcement_mode = {
        Deploy-Private-DNS-Zones = local.deploy_dns
      }
    }
  }
}

# Template file variable outputs
locals {
  template_file_variables = {
    private_dns_zone_prefix = local.private_dns_zone_prefix
  }
}

# Generate the configuration output object for the module
locals {
  module_output = {
    azurerm_resource_group = [
      for resource in local.azurerm_resource_group :
      {
        resource_id   = resource.resource_id
        resource_name = resource.name
        template = {
          for key, value in resource :
          key => value
          if local.deploy_resource_groups[resource.scope][resource.location] &&
          key != "resource_id" &&
          key != "managed_by_module" &&
          key != "scope"
        }
        managed_by_module = local.deploy_resource_groups[resource.scope][resource.location]
      }
    ]
    azurerm_virtual_network = [
      for resource in local.azurerm_virtual_network :
      {
        resource_id   = resource.resource_id
        resource_name = resource.name
        template = {
          for key, value in resource :
          key => value
          if local.deploy_hub_network[resource.location] &&
          key != "resource_id" &&
          key != "managed_by_module"
        }
        managed_by_module = local.deploy_hub_network[resource.location]
      }
    ]
    azurerm_subnet = [
      for resource in local.azurerm_subnet :
      {
        resource_id   = resource.resource_id
        resource_name = resource.name
        template = {
          for key, value in resource :
          key => value
          if local.deploy_hub_network[resource.location] &&
          key != "resource_id" &&
          key != "managed_by_module" &&
          key != "location" &&
          key != "network_security_group_id" &&
          key != "route_table_id"
        }
        managed_by_module = local.deploy_hub_network[resource.location]
      }
    ]
    azurerm_virtual_network_gateway = [
      for resource in local.azurerm_virtual_network_gateway :
      {
        resource_id   = resource.resource_id
        resource_name = resource.name
        template = {
          for key, value in resource :
          key => value
          if resource.managed_by_module &&
          key != "resource_id" &&
          key != "managed_by_module" &&
          key != "azurerm_public_ip"
        }
        managed_by_module = resource.managed_by_module
      }
    ]
    azurerm_public_ip = [
      for resource in local.azurerm_public_ip :
      {
        resource_id   = resource.resource_id
        resource_name = resource.name
        template = {
          for key, value in resource :
          key => value
          if resource.managed_by_module &&
          key != "resource_id" &&
          key != "managed_by_module"
        }
        managed_by_module = resource.managed_by_module
      }
    ]
    azurerm_firewall = [
      for resource in local.azurerm_firewall :
      {
        resource_id   = resource.resource_id
        resource_name = resource.name
        template = {
          for key, value in resource :
          key => value
          if resource.managed_by_module &&
          key != "resource_id" &&
          key != "managed_by_module" &&
          key != "azurerm_public_ip"
        }
        managed_by_module = resource.managed_by_module
      }
    ]
    azurerm_network_ddos_protection_plan = [
      for resource in local.azurerm_network_ddos_protection_plan :
      {
        resource_id   = resource.resource_id
        resource_name = resource.name
        template = {
          for key, value in resource :
          key => value
          if resource.managed_by_module &&
          key != "resource_id" &&
          key != "managed_by_module"
        }
        managed_by_module = resource.managed_by_module
      }
    ]
    azurerm_private_dns_zone = [
      for resource in local.azurerm_private_dns_zone :
      {
        resource_id   = resource.resource_id
        resource_name = resource.name
        template = {
          for key, value in resource :
          key => value
          if resource.managed_by_module &&
          key != "resource_id" &&
          key != "managed_by_module"
        }
        managed_by_module = resource.managed_by_module
      }
    ]
    azurerm_dns_zone = [
      for resource in local.azurerm_dns_zone :
      {
        resource_id   = resource.resource_id
        resource_name = resource.name
        template = {
          for key, value in resource :
          key => value
          if resource.managed_by_module &&
          key != "resource_id" &&
          key != "managed_by_module"
        }
        managed_by_module = resource.managed_by_module
      }
    ]
    azurerm_private_dns_zone_virtual_network_link = [
      for resource in local.azurerm_private_dns_zone_virtual_network_link :
      {
        resource_id   = resource.resource_id
        resource_name = resource.name
        template = {
          for key, value in resource :
          key => value
          if resource.managed_by_module &&
          key != "resource_id" &&
          key != "managed_by_module"
        }
        managed_by_module = resource.managed_by_module
      }
    ]
    azurerm_virtual_network_peering = [
      for resource in local.azurerm_virtual_network_peering :
      {
        resource_id   = resource.resource_id
        resource_name = resource.name
        template = {
          for key, value in resource :
          key => value
          if resource.managed_by_module &&
          key != "resource_id"
        }
        managed_by_module = resource.managed_by_module
      }
    ]
    archetype_config_overrides = local.archetype_config_overrides
    template_file_variables    = local.template_file_variables
  }
}

locals {
  debug_output = {
    deploy_resource_groups                        = local.deploy_resource_groups
    deploy_hub_network                            = local.deploy_hub_network
    deploy_virtual_network_gateway                = local.deploy_virtual_network_gateway
    deploy_virtual_network_gateway_expressroute   = local.deploy_virtual_network_gateway_expressroute
    deploy_virtual_network_gateway_vpn            = local.deploy_virtual_network_gateway_vpn
    deploy_azure_firewall                         = local.deploy_azure_firewall
    resource_group_names_by_scope_and_location    = local.resource_group_names_by_scope_and_location
    resource_group_config_by_scope_and_location   = local.resource_group_config_by_scope_and_location
    azurerm_resource_group                        = local.azurerm_resource_group
    ddos_resource_group_id                        = local.ddos_resource_group_id
    ddos_protection_plan_name                     = local.ddos_protection_plan_name
    ddos_protection_plan_resource_id              = local.ddos_protection_plan_resource_id
    azurerm_network_ddos_protection_plan          = local.azurerm_network_ddos_protection_plan
    hub_network_locations                         = local.hub_network_locations
    ddos_location                                 = local.ddos_location
    dns_location                                  = local.dns_location
    virtual_network_resource_group_id             = local.virtual_network_resource_group_id
    virtual_network_resource_id                   = local.virtual_network_resource_id
    azurerm_virtual_network                       = local.azurerm_virtual_network
    subnets_by_virtual_network                    = local.subnets_by_virtual_network
    azurerm_subnet                                = local.azurerm_subnet
    er_gateway_name                               = local.er_gateway_name
    er_gateway_resource_id                        = local.er_gateway_resource_id
    er_gateway_config                             = local.er_gateway_config
    vpn_gateway_name                              = local.vpn_gateway_name
    vpn_gateway_resource_id                       = local.vpn_gateway_resource_id
    vpn_gateway_config                            = local.vpn_gateway_config
    azurerm_virtual_network_gateway               = local.azurerm_virtual_network_gateway
    azfw_name                                     = local.azfw_name
    azfw_resource_id                              = local.azfw_resource_id
    azurerm_firewall                              = local.azurerm_firewall
    azurerm_public_ip                             = local.azurerm_public_ip
    enable_private_link_by_service                = local.enable_private_link_by_service
    private_link_locations                        = local.private_link_locations
    lookup_private_link_dns_zone_by_service       = local.lookup_private_link_dns_zone_by_service
    lookup_private_link_group_id_by_service       = local.lookup_private_link_group_id_by_service
    services_by_private_link_dns_zone             = local.services_by_private_link_dns_zone
    private_dns_zone_enabled                      = local.private_dns_zone_enabled
    azurerm_private_dns_zone                      = local.azurerm_private_dns_zone
    azurerm_dns_zone                              = local.azurerm_dns_zone
    hub_virtual_networks_for_dns                  = local.hub_virtual_networks_for_dns
    spoke_virtual_networks_for_dns                = local.spoke_virtual_networks_for_dns
    virtual_networks_for_dns                      = local.virtual_networks_for_dns
    azurerm_private_dns_zone_virtual_network_link = local.azurerm_private_dns_zone_virtual_network_link
  }
}

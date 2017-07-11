=begin
 list_openstack_securitygroup_ids.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method lists OpenStack security group ids
-------------------------------------------------------------------------------
   Copyright 2017 Kevin Morey <kevin@redhat.com>

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-------------------------------------------------------------------------------
=end
def log(level, msg, update_message = false)
  $evm.log(level, "#{msg}")
  @task.message = msg if @task && (update_message || level == 'error')
end

def get_provider(provider_id=nil)
  $evm.root.attributes.detect { |k,v| provider_id = v if k.end_with?('provider_id') } rescue nil
  provider = $evm.vmdb(:ManageIQ_Providers_Openstack_CloudManager).find_by_id(provider_id)
  log(:info, "Found provider: #{provider.name} via provider_id: #{provider.id}") if provider

  unless provider
    provider = $evm.vmdb(:ManageIQ_Providers_Openstack_CloudManager).first
    log(:info, "Found provider: #{provider.name} via default method") if provider
  end
  provider ? (return provider) : bail_out('< No providers found, check RBAC tags >')
end

def get_provider_from_template(template_guid=nil)
  $evm.root.attributes.detect { |k,v| template_guid = v if k.end_with?('_guid') } rescue nil
  template = $evm.vmdb(:ManageIQ_Providers_Openstack_CloudManager_Template).find_by_guid(template_guid)
  return nil unless template
  provider = $evm.vmdb(:ManageIQ_Providers_Openstack_CloudManager).find_by_id(template.ems_id)
  log(:info, "Found provider: #{provider.name} via template.ems_id: #{template.ems_id}") if provider
  provider ? (return provider) : (return nil)
end

def query_catalogitem(option_key, option_value=nil)
  # use this method to query a catalogitem
  # note that this only works for items not bundles since we do not know which item within a bundle to query from
  service_template = $evm.root['service_template']
  unless service_template.nil?
    begin
      if service_template.service_type == 'atomic'
        log(:info, "Catalog item: #{service_template.name}")
        service_template.service_resources.each do |catalog_item|
          catalog_item_resource = catalog_item.resource
          if catalog_item_resource.respond_to?('get_option')
            option_value = catalog_item_resource.get_option(option_key)
          else
            option_value = catalog_item_resource[option_key] rescue nil
          end
          log(:info, "Found {#{option_key} => #{option_value}}") if option_value
        end
      else
        log(:info, "Catalog bundle: #{service_template.name} found, skipping query")
      end
    rescue
      return nil
    end
  end
  option_value ? (return option_value) : (return nil)
end

def get_tenant(tenant_id=nil)
  $evm.root.attributes.detect { |k,v| tenant_id = v if k.end_with?('cloud_tenant') } rescue nil
  tenant = $evm.vmdb(:cloud_tenant).find_by_id(tenant_id)
  log(:info, "Found tenant: #{tenant.name} via tenant_id: #{tenant.id}") if tenant
  tenant ? (return tenant) : bail_out('< No tenants found, check RBAC tags >')
end

def bail_out(message)
  dialog_hash = {}
  dialog_hash[''] = message
  $evm.object['required'] = false
  set_values_and_exit(dialog_hash)
  exit MIQ_WARN
end

def set_values_and_exit(dialog_hash)
  $evm.object["values"] = dialog_hash
  log(:info, "$evm.object['values']: #{$evm.object['values'].inspect}")
  $evm.object['default_value'] = dialog_hash.first[0]
end

def check_rbac
  rbac = $evm.object['enable_rbac'] || false
  if rbac
    $evm.enable_rbac
  else
    $evm.disable_rbac
  end
  log(:info, "$evm.rbac_enabled?: #{$evm.rbac_enabled?}")
end

$evm.root.attributes.sort.each { |k, v| log(:info, "\t Attribute: #{k} = #{v}")}

# check service model for rbac control
check_rbac

dialog_hash = {}
provider = get_provider(query_catalogitem(:src_ems_id)) || get_provider_from_template()

if provider
  tenant = get_tenant(query_catalogitem(:cloud_tenant))

  tenant.security_groups.each do |security_group|
    dialog_hash[security_group.id] = "#{security_group.name} on #{tenant.name}@#{provider.name}"
  end
else
  # no provider so list everything
  $evm.vmdb(:ManageIQ_Providers_Openstack_NetworkManager_SecurityGroup).all.each do |security_group|
    next unless security_group.ext_management_system || security_group.name
    dialog_hash[security_group.id] = "#{security_group.name} on #{security_group.ext_management_system.name}"
  end
end

if dialog_hash.blank?
  bail_out("< No security groups found, check RBAC tags >")
else
  set_values_and_exit(dialog_hash)
end

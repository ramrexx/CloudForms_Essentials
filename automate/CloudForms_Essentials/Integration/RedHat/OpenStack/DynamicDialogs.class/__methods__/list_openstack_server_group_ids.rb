=begin
  list_openstack_server_group_ids.rb

  Author: David Costakos <dcostako@redhat.com>, Kevin Morey <kmorey@redhat.com>

  Description: Build list of Openstack server groups

-------------------------------------------------------------------------------
   Copyright 2016 Kevin Morey <kmorey@redhat.com>

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
  provider = $evm.vmdb(:ems_openstack).find_by_id(provider_id)
  log(:info, "Found provider: #{provider.name} via provider_id: #{provider.id}") if provider
  # set to true to default to the admin tenant
  use_default = true
  unless provider
    # default the provider to first openstack provider
    provider = $evm.vmdb(:ems_openstack).first if use_default
    log(:info, "Found provider: #{provider.name} via default method") if provider && use_default
  end
  provider ? (return provider) : (return nil)
end

def get_tenant(tenant_category, tenant_id=nil)
  # get the cloud_tenant id from $evm.root if already set
  $evm.root.attributes.detect { |k,v| tenant_id = v if k.end_with?('cloud_tenant') } rescue nil
  tenant = $evm.vmdb(:cloud_tenant).find_by_id(tenant_id)
  log(:info, "Found tenant: #{tenant.name} via tenant_id: #{tenant.id}") if tenant

  unless tenant
    # get the tenant name from the group tenant tag
    group = $evm.root['user'].current_group
    tenant_tag = group.tags(tenant_category).first rescue nil
    tenant = $evm.vmdb(:cloud_tenant).find_by_name(tenant_tag) rescue nil
    log(:info, "Found tenant: #{tenant.name} via group: #{group.description} tagged_with: #{tenant_tag}") if tenant
  end

  # set to true to default to the admin tenant
  use_default = true
  unless tenant
    tenant = $evm.vmdb(:cloud_tenant).find_by_name('admin') if use_default
    log(:info, "Found tenant: #{tenant.name} via default method") if tenant && use_default
  end
  tenant ? (return tenant) : (return nil)
end

def get_fog_object(type='Compute', tenant='admin', endpoint='adminURL')
  require 'fog/openstack'
  (@provider.api_version == 'v2') ? (conn_ref = '/v2.0/tokens') : (conn_ref = '/v3/auth/tokens')
  (@provider.security_protocol == 'non-ssl') ? (proto = 'http') : (proto = 'https')

  connection_hash = {
    :openstack_api_key => @provider.authentication_password,
    :openstack_username => @provider.authentication_userid,
    :openstack_auth_url => "#{proto}://#{@provider.hostname}:#{@provider.port}#{conn_ref}",
    :openstack_tenant => tenant,
  }
  connection_hash[:openstack_endpoint_type] = endpoint if type == 'Identity'
  # if the openstack environment is using keystone v3, add two keys to hash and replace the auth_url
  if @provider.api_version == 'v3'
    connection_hash[:openstack_domain_name] = 'Default'
    connection_hash[:openstack_project_name] = tenant
    connection_hash[:openstack_auth_url] = "#{proto}://#{@provider.hostname}:35357/#{conn_ref}"
  end
  return Object::const_get("Fog").const_get("#{type}").const_get("OpenStack").new(connection_hash)
end

def list_groups(nova_url, token)
  log(:info, "Entering method list_groups")
  require 'rest-client'
  require 'json'
  params = {
    :method => "GET",
    :url => "#{nova_url}/os-server-groups",
    :headers => { :content_type => :json, :accept => :json, 'X-Auth-Token' => "#{token}" }
  }
  response = RestClient::Request.new(params).execute
  json = JSON.parse(response)
  log(:info, "Full Response #{JSON.pretty_generate(json)}")
  log(:info, "Exiting method list_groups")
  return json['server_groups']
end

log(:info, "Begin Automate Method")

provider = get_provider()

tenant_category = $evm.object['tenant_category'] || 'tenant'
tenant = get_tenant(tenant_category)
tenant_name = tenant
tenant_name = tenant.name if tenant.respond_to?('name')

conn = get_fog_object(provider, "Compute", tenant_name)
token = conn.instance_variable_get(:@auth_token)
nova_url = conn.instance_variable_get(:@openstack_management_url)

groups = list_groups(nova_url, token)
log(:info, "All Groups: #{groups.inspect}")
dialog_hash = {}
groups.each { |group| dialog_hash[group["id"]] = "#{group["name"]} on #{provider.name}" }
dialog_hash[''] = "< Choose >"
$evm.object['values'] = dialog_hash
log(:info, "Set Dialog Hash to #{dialog_hash.inspect}")
log(:info, "Automate Method Ended")

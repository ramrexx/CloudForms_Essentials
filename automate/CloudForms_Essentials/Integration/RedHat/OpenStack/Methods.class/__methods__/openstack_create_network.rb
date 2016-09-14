=begin
  openstack_create_network.rb

  Author: Nate Stephany <nate@redhat.com>, Kevin Morey <kevin@redhat.com>

  Description: This method creates basic networking for a newly created
               OpenStack tenant

  Mandatory dialog fields: external_net, subnet_range, subnet_gateway

-------------------------------------------------------------------------------
   Copyright 2016 Kevin Morey <kevin@redhat.com>

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

def get_provider(provider_id=nil)
  if provider_id.blank?
    $evm.root.attributes.detect { |k,v| provider_id = v if k.end_with?('provider_id') } rescue nil
  end
  provider = $evm.vmdb(:ManageIQ_Providers_Openstack_CloudManager).find_by_id(provider_id)
  if provider.nil?
    provider = $evm.vmdb(:ManageIQ_Providers_Openstack_CloudManager).first
    log(:info, "Found provider: #{provider.name} via default method") if provider
  else
    log(:info, "Found provider: #{provider.name} via provider_id: #{provider.id}") if provider
  end
  provider ? (return provider) : (return nil)
end

def update_status_lite(options_hash)
  log(:info, "updating status: #{options_hash['status']}", true) unless options_hash['status'].blank?
  $evm.set_state_var(:options_hash, options_hash)
  log(:info, "Workspace variable updated {:options_hash=>#{$evm.get_state_var(:options_hash)}")
end

def create_tenant_net(options_hash)
  openstack_neutron = get_fog_object('Network')
  openstack_keystone = get_fog_object('Identity')
  
  # create router first using the external network provided in dialog
  router = openstack_neutron.create_router("#{options_hash["tenant_name"]}_router",
    {
      :tenant_id => options_hash["tenant_id"],
      :external_gateway_info => 
        {
          :network_id => options_hash["public_network"]
        }
    }
  )[:body]["router"]

  # next we will create the tenant network and subnet provided in dialog
  tenant_net = openstack_neutron.create_network(
    {
      :name => "#{options_hash["tenant_name"]}_net",
      :tenant_id => options_hash["tenant_id"]
    }
  )[:body]["network"]
  tenant_subnet = openstack_neutron.create_subnet(tenant_net["id"], "#{options_hash["tenant_subnet"]}", 4,
    {
      :name => "#{tenant_net["name"]}-subnet",
      :gateway_ip => "#{options_hash["tenant_gateway"]}",
      :tenant_id => options_hash["tenant_id"],
      :enable_dhcp => true
    }
  )[:body]["subnet"]

  # finally, we will add the interface to the router so it can talk on the tenant network
  openstack_neutron.add_router_interface(router["id"], tenant_subnet["id"])
  log(:info, "added router: #{router["name"]}, network: #{tenant_net["name"]}, & subnet: #{tenant_subnet["name"]}")
end

begin
  #dump all of the attributes from the root object to see what we are working with
  $evm.root.attributes.sort.each { |k, v| log(:info, "\t $evm.root Attribute - #{k}: #{v}")}

  case $evm.root['vmdb_object_type']
  when 'service_template_provision_task'
    # Executed via generic service catalog item
    @task = $evm.root['service_template_provision_task']
    @service = @task.destination
    log(:info, "Service #{@service.name} id: #{@service.id} tasks: #{@task.miq_request_tasks.count}")
    # options_hash is used to collect information along the way for reuse
    $evm.get_state_var(:options_hash).blank? ? (options_hash = {}) : (options_hash = $evm.get_state_var(:options_hash))
    # giving the option to set these in the dialog or rely on more default values
    admin_tenant = $evm.root['dialog_admin_tenant'] || options_hash['admin_tenant'] || 'admin'
    provider_id = $evm.root['dialog_provider_id'] || options_hash['provider_id']
    @provider = get_provider(provider_id)
  else
    exit MIQ_OK
  end

  raise "missing provider: #{@provider}" if @provider.nil?

  create_network = $evm.root['dialog_create_network'] || options_hash['create_network']
  # update options_hash with dialog values
  options_hash["public_network"] = $evm.root['dialog_public_network']
  options_hash["tenant_subnet"] = $evm.root['dialog_tenant_subnet']
  options_hash["tenant_gateway"] = $evm.root['dialog_tenant_gateway']

  options_hash.each { |k, v| log(:info, "options_hash contents - #{k}: #{v}")}

  unless create_network == 'f'
    create_tenant_net(options_hash)
  end

  options_hash['status'] = log(:info, "Network elements created for tenant: #{options_hash["tenant_name"]}")

  @provider.refresh
  update_status_lite(options_hash)

rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
end

=begin
  list_openstack_external_net_ids.rb

  Author: Nate Stephany <nate@redhat.com>, Kevin Morey <kevin@redhat.com>

  Description: This method pulls back a list of OpenStack external networks
               and passes the ID

  Mandatory dialog fields: none
  Optional dialog fields: none
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
  # if we get pass the provider_id when calling the method...
  if provider_id
    provider = $evm.vmdb(:ManageIQ_Providers_Openstack_CloudManager).find_by_id(provider_id)
  else
    # otherwise, pull the provider_id from the dialog options
    $evm.root.attributes.detect { |k,v| provider_id = v if k.end_with?('provider_id') } rescue nil
    provider = $evm.vmdb(:ManageIQ_Providers_Openstack_CloudManager).find_by_id(provider_id)
  end

  if provider
    log(:info, "Found provider: #{provider.name} via provider_id: #{provider.id}")
  else
    # if all else fails, grab the first provider of this type
    provider = $evm.vmdb(:ManageIQ_Providers_Openstack_CloudManager).first
    log(:info, "Found provider: #{provider.name} via default method")
  end
  provider ? (return provider) : (return nil)
end

$evm.root.attributes.sort.each { |k, v| log(:info, "\t Attribute: #{k} = #{v}")}

@provider = get_provider

dialog_hash = {}

# gathering some basic variables for use here and there
log(:info, "provider: #{@provider.name} provider id: #{@provider.id}")

openstack_neutron = get_fog_object('Network')
ext_net_list = openstack_neutron.list_networks.body["networks"].select do |net|
  net["router:external"] == true
end
ext_net_list.each do |net|
  dialog_hash[net["id"]] = "#{net["name"]} in #{@provider.name}"
end

if dialog_hash.blank?
  dialog_hash[''] = "< No External Nets found. Contact Admin >"
else
  $evm.object['default_value'] = dialog_hash.first[0]
end

$evm.object['values'] = dialog_hash
log(:info, "$evm.object['values']: #{$evm.object['values'].inspect}")

=begin
  list_openstack_attached_volumes_ids.rb

  Author: Kevin Morey <kevin@redhat.com>

  Description: This method lists all attached Cinder volumes for a vm
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

@vm = $evm.root['vm']
raise "VM is nil from $evm.root['vm']" if @vm.nil?
@provider = @vm.ext_management_system
tenant = $evm.vmdb(:cloud_tenant).find_by_id(@vm.cloud_tenant_id)
$evm.log(:info, "vm: #{@vm.name} provider: #{@provider.name} tenant: #{tenant.name}")

openstack_nova = get_fog_object('Compute', tenant.name)
openstack_cinder = get_fog_object('Volume', tenant.name)

dialog_hash = {}
attachments = openstack_nova.get_server_details(@vm.ems_ref).body['server']['os-extended-volumes:volumes_attached']
$evm.log(:info, "vm: #{@vm.name} volumes: #{attachments}")
for attachment in attachments
  details = openstack_cinder.get_volume_details(attachment['id']).body['volume']
  dialog_hash[attachment['id']] = "[#{details['display_name']}:#{details['attachments'][0]['device']}]"
end

$evm.log(:info, "#{dialog_hash}")
if dialog_hash.blank?
  $evm.log(:info, "No attached volumes: #{attachments.inspect}")
  dialog_hash[''] = "no volumes to detach"
end
$evm.object['default_value'] = dialog_hash.first[0]
$evm.object['values'] = dialog_hash
$evm.log(:info, "Dynamic values: #{$evm.object['values']}")

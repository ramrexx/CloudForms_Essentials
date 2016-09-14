=begin
  openstack_resize_instance.rb

  Author: Dave Costakos <david.costakos@redhat.com>, Kevin Morey <kevin@redhat.com>

  Description: This method is used to change the flavor of an openstack instance. Note that flavors can only be increased
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

def dump_root()
  log(:info, "Begin $evm.root.attributes")
  $evm.root.attributes.sort.each { |k, v| log(:info, "\t Attribute: #{k} = #{v}")}
  log(:info, "End $evm.root.attributes")
  log(:info, "")
end

def set_ae_options_hash(hash)
  log(:info, "Adding {#{hash}} to ae_workspace: #{@ae_state_var}", true)
  $evm.set_state_var(@state_var, hash)
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

begin
  $evm.root.attributes.sort.each { |k, v| log(:info, "\t $evm.root Attribute - #{k}: #{v}")}
  @vm  = $evm.root['vm']
  raise "vm not found" if @vm.nil?
  log(:info, "Found VM: #{@vm.name} vendor: #{@vm.vendor}")

  @provider  = @vm.ext_management_system
  original_flavor = @vm.flavor
  dialog_flavor = $evm.root['dialog_flavor']
  new_flavor = $evm.vmdb(:ManageIQ_Providers_Openstack_CloudManager_Flavor).find_by_id(dialog_flavor) ||
    $evm.vmdb(:ManageIQ_Providers_Openstack_CloudManager_Flavor).find_by_name(dialog_flavor)
  tenant = $evm.vmdb(:cloud_tenant).find_by_id(@vm.cloud_tenant_id)

  # $evm.set_state_var(:original_flavor_id, @vm.flavor_id)
  log(:info, "VM: #{@vm.name} ems_ref: #{@vm.ems_ref} tenant id: #{@vm.cloud_tenant_id} original_flavor: #{original_flavor.name} new_flavor: #{new_flavor.name}")
  compute_conn = get_fog_object("Compute", tenant.name)
  log(:info, "Resizing VM: #{@vm.name} to #{new_flavor.name}")
  resize_details = compute_conn.resize_server(@vm.ems_ref, new_flavor.ems_ref)
  log(:info, "resize_details: #{resize_details.inspect}")
  vm_details = compute_conn.get_server_details(@vm.ems_ref)
  log(:info, "vm_details: #{vm_details.inspect}")
  @vm.refresh

  # Set Ruby rescue behavior
rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

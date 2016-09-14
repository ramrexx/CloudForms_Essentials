=begin
  openstack_clone_vm.rb

  Author: Nate Stephany <nate@redhat.com>, Kevin Morey <kevin@redhat.com>

  Description: This method clones a number of OpenStack instances that are
               backed by Cinder volumes. Currently only clones within 
               source tenant.

  Mandatory dialog fields: e_vm_name_X, n_vm_name_X (X = 1, 2, 3, etc.)
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

def get_tenant()
  ws_values = @task.options.fetch(:ws_values, {})
  cloud_tenant_search_criteria = @task.get_option(:cloud_tenant_id) || ws_values[:cloud_tenant_id] ||
    @task.get_option(:cloud_tenant) || ws_values[:cloud_tenant] || 'admin' rescue 'admin'
  tenant = $evm.vmdb(:cloud_tenant).find_by_id(cloud_tenant_search_criteria) ||
    $evm.vmdb(:cloud_tenant).find_by_name(cloud_tenant_search_criteria) ||
    $evm.vmdb(:cloud_tenant).all.detect { |ct| ct.name.casecmp(cloud_tenant_search_criteria)==0 }
  return tenant

  # future code changes start here
  #user = $evm.root(:user)

  #to get based on actual tenant group is assiged to
  #return user.current_tenant

  #to get based on tags of group that user is assigned to
  #return user.current_group
end

def get_volume_id(tenant='admin', vm_id)
  openstack_nova = get_fog_object('Compute', tenant.name)
  log(:info, "Looking in tenant: #{tenant.name} for volumes")
  volume = openstack_nova.get_server_volumes(vm_id)[:body]["volumeAttachments"]
  volume_id = volume.first.fetch("volumeId")
  log(:info, "The volume ID of #{vm_id} is #{volume_id}")

  return volume_id
end

def cinder_snapshot(tenant='admin', vm_vol_id, existing_vm_id)
  #create snapshot of vm_name and return uuid of new cinder volume
  openstack_cinder = get_fog_object('Volume', tenant.name)
  snapshot = openstack_cinder.create_volume_snapshot("#{vm_vol_id}", "Snapshot of VM #{existing_vm_id} disk", "Snapshot created at #{Time.new}", true)
  snapshot_id = snapshot[:body]["snapshot"].fetch("id")
  log(:info, "Created snapshot of #{existing_vm_id} disk")
  return snapshot_id

  # save for later when introducing cloning between tenants
  #snapshot_size = snapshot[:body]["snapshot"].fetch("size")
  #new_volume = openstack_cinder.create_volume("#{existing_vm_name}-vol$n{3}", "CloudForms created volume for #{new_vm_name}",
  #  snapshot_size, options={:snapshotId => snapshot_id})
  #new_volume_id = new_volume.body["volume"].fetch("id")
  #return new_volume_id
end

def create_vm_from_snap(tenant='admin', vm_snap_id, new_vm_name, existing_vm_id)
  openstack_nova = get_fog_object('Compute', tenant.name)
  openstack_neutron = get_fog_object('Network', tenant.name)
  vm_details = openstack_nova.get_server_details(existing_vm_id)[:body]["server"]
  flavor_id = vm_details["flavor"]["id"]
  net_id = openstack_neutron.list_ports.body["ports"].detect { |port| port["device_id"] == "#{existing_vm_id}" }["network_id"]

  new_vm = openstack_nova.servers.create(
    {
      :name                    => "#{new_vm_name}",
      :flavor_ref              => "#{flavor_id}",
      :nics                    => [{"net_id"=>"#{net_id}"}],
      :block_device_mapping_v2 => [
        {
          :boot_index            => 0,
          :device_name           => "vda",
          :source_type           => "snapshot",
          :destination_type      => "volume",
          :delete_on_termination => false,
          :uuid                  => "#{vm_snap_id}",
        }
      ]
    }
  )
  new_vm.wait_for { ready? }
  return new_vm.name
end

begin
  $evm.root.attributes.sort.each { |k, v| log(:info, "\t $evm.root Attribute - #{k}: #{v}")}

  case $evm.root['vmdb_object_type']
  when 'service_template_provision_task'
    # Executed via generic service catalog item
    @task = $evm.root['service_template_provision_task']
    @service = @task.destination
    log(:info, "Service: #{@service.name} id: #{@service.id} tasks: #{@task.miq_request_tasks.count}")
    $evm.get_state_var(:options_hash).blank? ? (options_hash = {}) : (options_hash = $evm.get_state_var(:options_hash))
    admin_tenant = $evm.root['dialog_admin_tenant'] || options_hash['admin_tenant'] || 'admin'
    provider_id =  $evm.root['dialog_provider_id'] || options_hash['provider_id']
    tenant_name =  $evm.root['dialog_tenant_name'] || options_hash['tenant_name']
    tenant_description = $evm.root['dialog_tenant_description'] || options_hash['tenant_description']

    @provider = get_provider(provider_id)
  else
    exit MIQ_OK
  end

  tenant = get_tenant
  raise "no tenant found" if tenant.nil?

  log(:info, "provider: #{@provider.name}, tenant: #{tenant.name}")
  existing_vm_regex = /e_vm_name_\d/
  new_vm_regex = /n_vm_name_\d/

  existing_vms_hash = {}
  $evm.root.attributes.each { |k,v| existing_vms_hash[k] = v if k.to_s =~ existing_vm_regex }
  log(:info, "Inspecting existing_vms_hash: #{existing_vms_hash.inspect}")
  existing_vms_hash.keys.each { |k| existing_vms_hash[k.sub(/dialog_/, '')] = existing_vms_hash[k]; existing_vms_hash.delete(k) }
  log(:info, "New existing_vms_hash: #{existing_vms_hash.inspect}")
  existing_vms_hash.each { |k,v| existing_vms_hash.delete(k) if v.empty? }

  new_vms_hash = {}
  $evm.root.attributes.each { |k,v| new_vms_hash[k] = v if k.to_s =~ new_vm_regex }
  log(:info, "Inspecting new_vms_hash: #{new_vms_hash.inspect}")
  new_vms_hash.keys.each { |k| new_vms_hash[k.sub(/dialog_/, '')] = new_vms_hash[k]; new_vms_hash.delete(k) }
  log(:info, "New new_vms_hash: #{new_vms_hash.inspect}")
  new_vms_hash.each { |k,v| new_vms_hash.delete(k) if v.empty? }
  
  unless existing_vms_hash.nil?
    existing_vms_hash.each do |k,v|
      e_vm_id = v
      log(:info, "Current existing VM ID is: #{e_vm_id}")
      search = k.gsub(/e_vm_name/, 'n_vm_name')
      n_vm_name = new_vms_hash[search]
      log(:info, "Current new VM is: #{n_vm_name}")
      vm_vol = get_volume_id(tenant, e_vm_id)
      vm_snap = cinder_snapshot(tenant, vm_vol, e_vm_id)
      new_vm = create_vm_from_snap(tenant, vm_snap, n_vm_name, e_vm_id)
      log(:info, "VM #{new_vm} successfully created from snapshot")
    end
  end
  @provider.refresh
  
rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

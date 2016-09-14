=begin
  openstack_delete_volume.rb

  Author: Kevin Morey <kevin@redhat.com>

  Description: This method is used to delete openstack volume(s)
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

def get_tenant()
  ws_values = @task.options.fetch(:ws_values, {})
  tenant_id = @task.get_option(:cloud_tenant_id) || ws_values[:cloud_tenant_id] rescue nil
  tenant_id ||= @task.get_option(:cloud_tenant) || ws_values[:cloud_tenant] rescue nil
  unless tenant_id.nil?
    tenant = $evm.vmdb(:cloud_tenant).find_by_id(tenant_id)
    log(:info, "Using tenant: #{tenant.name} id: #{tenant.id} ems_ref: #{tenant.ems_ref}")
  else
    tenant = $evm.vmdb(:cloud_tenant).find_by_name('admin')
    log(:info, "Using default tenant: #{tenant.name} id: #{tenant.id} ems_ref: #{tenant.ems_ref}")
  end
  return tenant
end

begin
  $evm.root.attributes.sort.each { |k, v| log(:info, "\t $evm.root Attribute - #{k}: #{v}")}

  case $evm.root['vmdb_object_type']
  when 'miq_provision'
    @task = $evm.root['miq_provision']
    log(:info, "Task: #{@task.id} Request: #{@task.miq_request.id} Type:#{@task.type}")
    @vm = @task.vm
    retry_method(15.seconds, "Waiting for vm: #{@task.get_option(:vm_target_name)}") if @vm.nil?
    tenant = get_tenant
    created_volumes = @task.options[:created_volumes] || []
  when 'vm'
    # get vm from root
    @vm = $evm.root['vm']
    @task  = @vm.miq_provision
    tenant = $evm.vmdb(:cloud_tenant).find_by_id(@vm.cloud_tenant_id) ||
      $evm.vmdb(:cloud_tenant).all.detect { |ct| ct.name.casecmp('admin')==0 }
    created_volumes = @task.options[:created_volumes] rescue []
    if created_volumes.blank?
      created_volumes = []
      compute_conn = get_fog_object('Compute', tenant.name)
      attached_volumes = compute_conn.get_server_details(@vm.ems_ref).body['server']['os-extended-volumes:volumes_attached']
      log(:info, "vm: #{@vm.name} volumes: #{attachments}")
      attached_volumes.each {|volume| created_volumes << volume['id'] }
    end
  else
    exit MIQ_OK
  end
  raise "no tenant found" if tenant.nil?

  @provider = @vm.ext_management_system
  log(:info, "created_volumes: #{created_volumes.inspect}")

  openstack_volume = get_fog_object('Volume', tenant.name)

  unless created_volumes.blank?
    created_volumes.each do |volume_uuid|
      log(:info, "Checking status for volume: #{volume_uuid}", true)
      begin
        volume_details = openstack_volume.get_volume_details(volume_uuid).body['volume']
        log(:info, "Volume Details: #{volume_details.inspect}")
        log(:info, "Volume Status is #{volume_details['status']}", true)
        if volume_details['status'] == 'available'
          log(:info, "Deleting Volume: #{volume_uuid} on VM: #{vm.name}", true)
          openstack_volume.delete_volume(volume_uuid)
        end
        if volume_details['status'] == 'in-use'
          log(:warn, "Volume: #{volume_uuid} still attached", true)
        end
      rescue Fog::Compute::OpenStack::NotFound => gooderr
        log(:info, "Volume does not exist: #{gooderr}")
      end
    end
  end

  # Set Ruby rescue behavior
rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_STOP
end

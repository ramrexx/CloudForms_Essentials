=begin
  openstack_attach_volume_check.rb

  Author: David Costakos <dcostako@redhat.com>, Kevin Morey <kevin@redhat.com>

  Description: This method checks that the Cinder volume(s) have been attached
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

def retry_method(retry_time, msg='INFO')
  log(:info, "#{msg} - Waiting #{retry_time} seconds}", true)
  $evm.root['ae_result'] = 'retry'
  $evm.root['ae_retry_interval'] = retry_time
  exit MIQ_OK
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
  cloud_tenant_search_criteria = @task.get_option(:cloud_tenant_id) || ws_values[:cloud_tenant_id] ||
    @task.get_option(:cloud_tenant) || ws_values[:cloud_tenant] rescue 'admin'
  tenant = $evm.vmdb(:cloud_tenant).find_by_id(cloud_tenant_search_criteria) ||
    $evm.vmdb(:cloud_tenant).find_by_name(cloud_tenant_search_criteria) ||
    $evm.vmdb(:cloud_tenant).all.detect { |ct| ct.name.casecmp(cloud_tenant_search_criteria)==0 }
  return tenant
end

begin
  $evm.root.attributes.sort.each { |k, v| log(:info, "\t $evm.root Attribute - #{k}: #{v}")}

  case $evm.root['vmdb_object_type']
  when 'miq_provision'
    @task = $evm.root['miq_provision']
    log(:info, "Task: #{@task.id} Request: #{@task.miq_request.id} Type:#{@task.type}")
    @vm = @task.vm
    retry_method(15.seconds, "Waiting for VM: #{@task.get_option(:vm_target_name)}") if @vm.nil?
    tenant = get_tenant
    attach_volumes = @task.options[:created_volumes] || []
  when 'vm'
    # get vm from root
    @vm = $evm.root['vm']
    tenant = $evm.vmdb(:cloud_tenant).find_by_id(@vm.cloud_tenant_id)
    attach_volumes = $evm.get_state_var(:attach_volumes) || []
    if attach_volumes.blank?
      attach_volumes = []
      get_volume_options_hash.each do |boot_index, volume_options|
        attach_volumes << volume_options[:uuid]
      end
    end
  else
    exit MIQ_OK
  end
  raise "no tenant found" if tenant.nil?

  @provider  = @vm.ext_management_system
  log(:info, "provider: #{@provider.name} tenant: #{tenant.name}")
  log(:info, "attach_volumes: #{attach_volumes.inspect}")

  unless attach_volumes.blank?
    volume_conn = get_fog_object('Volume', tenant.name)
    compute_conn = get_fog_object('Compute', tenant.name)
    attach_volumes.each do |volume_uuid|
      log(:info, "checking status for volume: #{volume_uuid}", true)
      volume_details = volume_conn.get_volume_details(volume_uuid).body['volume']
      log(:info, "volume Details: #{volume_details.inspect}")
      log(:info, "volume #{volume_uuid} status: #{volume_details['status']}", true)
      if volume_details['status'] == "in-use"
        log(:info, "volume: #{volume_uuid} successfully attached", true)
      elsif volume_details['status'] == "error"
        raise "Volume attach failed for #{volume_uuid}"
      else
        retry_method('15.seconds', "Volume Status: #{volume_details['status']}")
      end
    end

    volumes_attached = compute_conn.get_server_details(@vm.ems_ref).body['server']['os-extended-volumes:volumes_attached']
    log(:info, "vm: #{@vm.name} volumes_attached: #{volumes_attached}")
    volume_number = 0
    volumes_attached.each do |volume|
      volume_details = volume_conn.get_volume_details(volume['id']).body['volume']
      log(:info, "volume_details: #{volume_details}")
      log(:info, "volume_details['attachments']: #{volume_details['attachments']}")
      @vm.custom_set("CINDER_volume_#{volume_number}", "#{volume_details['display_name']}:#{volume_details['attachments'][0]['device']}")
      volume_number += 1
    end
    @vm.refresh
  end

rescue => err
  log(:error, "[#{err.class}:#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

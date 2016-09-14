=begin
  openstack_create_volume_check.rb

  Author: Kevin Morey <kevin@redhat.com>

  Description: This method is used to check the creation of openstack volume(s)
     and add support for boot from volume
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

def add_volumes_to_clone_options
  # add created volumes and add them to the miq_provision clone_options
  log(:info, "Processing add_volumes...", true)
  volume_hash = @task.options[:volume_hash]
  log(:info, "volume_hash: #{volume_hash.inspect}")

  unless volume_hash.blank?
    volume_array = []
    # pull out boot volume 0 hash for later processing
    boot_volume_size = volume_hash[0][:size].to_i rescue 0
    unless boot_volume_size.zero?
      # add extra volumes to volume_array
      volume_hash.each do |boot_index, volume_options|
        next if volume_options[:uuid].blank?
        (volume_options[:delete_on_termination] =~ (/(false|f|no|n|0)$/i)) ? (delete_on_termination = false) : (delete_on_termination = true)
        log(:info, "Processing boot_index: #{boot_index} - #{volume_options.inspect}")
        if boot_index.zero?
          boot_block_device = {
            :boot_index => boot_index,
            :source_type => 'volume',
            :destination_type => 'volume',
            :uuid => volume_options[:uuid],
            :delete_on_termination => delete_on_termination,
          }
          unless volume_options[:device_name] =~ (/(false|f|no|n|0)$/i)
            boot_block_device[:device_name] = volume_options[:device_name]
          end
          log(:info, "volume: #{boot_index} - boot_block_device: #{boot_block_device.inspect}")
          volume_array << boot_block_device
        else
          new_volume = { :boot_index => boot_index, :source_type => 'volume', :destination_type => 'volume', :uuid => volume_options[:uuid], :delete_on_termination => delete_on_termination }
          log(:info, "volume: #{boot_index} - new_volume: #{new_volume.inspect}")
          volume_array << new_volume
        end
      end
      unless volume_array.blank?
        clone_options = @task.get_option(:clone_options) || {}
        clone_options.merge!({ :image_ref => nil, :block_device_mapping_v2 => volume_array })
        @task.set_option(:clone_options, clone_options)
        log(:info, "Provisioning option updated {:clone_options => #{@task.options[:clone_options].inspect}}")
      end
    else
      log(:info, "Boot disk is ephemeral, skipping add_volumes as extra disks if any will be attached during post provisioning")
    end
  end
  log(:info, "Processing add_volumes...Complete", true)
end

begin
  $evm.root.attributes.sort.each { |k, v| log(:info, "\t $evm.root Attribute - #{k}: #{v}")}

  case $evm.root['vmdb_object_type']
  when 'miq_provision'
    @task = $evm.root['miq_provision']
    log(:info, "Task: #{@task.id} Request: #{@task.miq_request.id} Type:#{@task.type}")
    @vm = @task.vm_template
    tenant = get_tenant
    created_volumes = @task.options[:created_volumes] || []
    log(:info, "created_volumes: #{created_volumes.inspect}")
  when 'vm'
    # get vm from root
    @vm = $evm.root['vm']
    tenant = $evm.vmdb(:cloud_tenant).find_by_id(@vm.cloud_tenant_id)
    created_volumes = $evm.get_state_var(:created_volumes) || []
    log(:info, "{:created_volumes=>#{created_volumes}}")
  else
    exit MIQ_OK
  end
  raise "no tenant found" if tenant.nil?

  @provider  = @vm.ext_management_system
  log(:info, "provider: #{@provider.name} tenant: #{tenant.name}")

  unless created_volumes.blank?
    volume_conn = get_fog_object('Volume', tenant.name)
    created_volumes.each do |volume_uuid|
      log(:info, "Checking status for volume: #{volume_uuid}", true)
      volume_details = volume_conn.get_volume_details(volume_uuid).body['volume']
      log(:info, "Volume Details: #{volume_details.inspect}")
      log(:info, "Volume Status is #{volume_details['status']}", true)
      if volume_details['status'] == "available"
        log(:info, "Successfully created volume: #{volume_uuid}", true)
      elsif volume_details['status'] == "error"
        raise "Volume creation failed for #{volume_uuid}"
      else
        retry_method('15.seconds', "Volume Status: #{volume_details['status']}")
      end
    end
    $evm.set_state_var(:created_volumes, created_volumes)
    log(:info, "Workspace variable updated {:created_volumes=>#{$evm.get_state_var(:created_volumes)}}")
  else
    exit MIQ_OK
  end

  # add newly created volumes to the miq_provision clone_options
  add_volumes_to_clone_options if @task

  # Set Ruby rescue behavior
rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

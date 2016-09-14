=begin
 openstack_attach_volume.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method is used to attach openstack volume(s) 
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
  log(:info, "#{msg} - Waiting #{retry_time}", true)
  $evm.root['ae_result'] = 'retry'
  $evm.root['ae_retry_interval'] = retry_time
  exit MIQ_OK
end

def parse_hash(hash, volume_options_hash={})
  hash.each do |key, value|
    next if value.nil?
    if @regex =~ key
      option_index, paramter = $1.to_i, $2.to_sym
      log(:info, "option_index: #{option_index} - Adding option: {#{paramter.inspect}=>#{value.inspect}} to volume_options_hash")
      volume_options_hash[option_index] = {} unless volume_options_hash.key?(option_index)
      volume_options_hash[option_index][paramter] = value
    else
      log(:info, "key: #{key} value: #{value.inspect}")
    end
  end
  volume_options_hash
end

def get_volume_options_hash(volume_options_hash={})
  @regex = /volume_(\d*)_(.*)/
  if @task
    ws_values = @task.options.fetch(:ws_values, {})
    volume_options_hash = parse_hash(@task.options).merge(parse_hash(ws_values))
    log(:info, "Inspecting volume_options_hash: #{volume_options_hash.inspect}")
  else
    root_attributes_hash = {}
    $evm.root.attributes.each {|k, v| root_attributes_hash[k] = v if k.to_s =~ @regex }
    log(:info, "Inspecting root_attributes_hash: #{root_attributes_hash.inspect}")
    volume_options_hash = parse_hash(root_attributes_hash)
    log(:info, "Inspecting volume_options_hash: #{volume_options_hash.inspect}")
  end
  volume_options_hash
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

  case $evm.root['vmdb_object_type']
  when 'miq_provision'
    @task = $evm.root['miq_provision']
    log(:info, "Task: #{@task.id} Request: #{@task.miq_request.id} Type:#{@task.type}")
    @vm = @task.vm
    retry_method(15.seconds, "Waiting for VM: #{@task.get_option(:vm_target_name)}") if @vm.nil?
    attach_volumes = @task.options[:created_volumes] || []
  when 'vm'
    # get vm from root
    @vm = $evm.root['vm']

    attach_volumes = $evm.get_state_var(:created_volumes) || []
    if attach_volumes.blank?
      attach_volumes = []
      volume_hash = get_volume_options_hash()
      volume_hash.each do |boot_index, volume_options|
        attach_volumes << volume_options[:uuid]
      end
    end
    attach_volumes << $evm.root['dialog_volume_id'] if attach_volumes.blank?
  else
    exit MIQ_OK
  end
  tenant = $evm.vmdb(:cloud_tenant).find_by_id(@vm.cloud_tenant_id)
  raise "no tenant found" if tenant.nil?

  @provider  = @vm.ext_management_system
  log(:info, "provider: #{@provider.name} tenant: #{tenant.name}")
  log(:info, "attach_volumes: #{attach_volumes.inspect}")

  unless attach_volumes.blank?
    volume_conn = get_fog_object('Volume', tenant.name)
    compute_conn = get_fog_object('Compute', tenant.name)

    attach_volumes.each do |volume_uuid|
      log(:info, "Checking status for volume: #{volume_uuid}", true)
      volume_details = compute_conn.get_volume_details(volume_uuid).body['volume']
      log(:info, "Volume Details: #{volume_details.inspect}")
      log(:info, "Volume Status is #{volume_details['status']}", true)
      if volume_details['status'] == "available"
        log(:info, "Attaching Volume: #{volume_uuid} to VM: #{@vm.name}", true)
        compute_conn.attach_volume(volume_uuid, @vm.ems_ref, nil)
      else
        log(:info, "Volume: #{volume_uuid} already in-use", true)
      end
    end
    if @task
      @task.set_option(:volume_hash, volume_hash)
      @task.set_option(:attach_volumes, attach_volumes)
      log(:info, "volume_hash: #{@task.options[:volume_hash].inspect}")
      log(:info, "attach_volumes: #{@task.options[:attach_volumes].inspect}")
    else
      $evm.set_state_var(:volume_hash, volume_hash)
      log(:info, "Workspace variable updated {:volume_hash=>#{$evm.get_state_var(:volume_hash)}}")
      $evm.set_state_var(:attach_volumes, attach_volumes)
      log(:info, "Workspace variable updated {:attach_volumes=>#{$evm.get_state_var(:attach_volumes)}}")
    end
  else
    exit MIQ_OK
  end

  # Set Ruby rescue behavior
rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

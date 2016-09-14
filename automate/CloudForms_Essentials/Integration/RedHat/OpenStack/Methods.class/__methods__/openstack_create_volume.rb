=begin
  openstack_create_volume.rb

  Author: Kevin Morey <kevin@redhat.com>

  Description: This method is used to create openstack volume(s)
    exmaple1: volume_0_size =>20, volume_1_size=>50 (create a bootable 20GB volume 
              based on template and add an additional 50 empty volume)
    exmaple2: volume_0_size =>0, volume_1_size=>50 (clones the template (ephemeral) 
              and adds an additional 50 empty volume)
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
    @vm = @task.vm_template
    tenant = get_tenant
    vm_name = @task.get_option(:vm_target_name)
  when 'vm'
    # get vm from root
    @vm = $evm.root['vm']
    vm_name = @vm.name
    tenant = $evm.vmdb(:cloud_tenant).find_by_id(@vm.cloud_tenant_id)
  else
    exit MIQ_OK
  end
  raise "no tenant found" if tenant.nil?

  @provider  = @vm.ext_management_system
  log(:info, "provider: #{@provider.name} tenant: #{tenant.name}")

  created_volumes = []

  volume_hash = get_volume_options_hash()
  unless volume_hash.blank?
    volume_conn = get_fog_object("Volume", tenant.name)
    volume_hash.each do |boot_index, volume_options|
      # check boot_index and size
      if boot_index.zero?
        if volume_options[:size].to_i.zero?
          log(:info, "Boot disk is ephemeral, skipping volume... ")
          volume_options[:size] = 0
        else
          volume_options[:bootable] = true
          volume_options[:imageref] = @vm.ems_ref
        end
      else
        volume_options[:bootable] = false
        volume_options[:imageref] = nil
      end
      unless volume_options[:size].to_i.zero?
        volume_options[:name]         = "CloudForms created volume #{boot_index} for #{vm_name}"
        volume_options[:description]  = "#{volume_options[:name]} at #{Time.now}"
        log(:info, "Creating volume #{volume_options.inspect}")
        new_volume = volume_conn.create_volume(volume_options[:name], volume_options[:description], volume_options[:size], { :bootable => volume_options[:bootable], :imageRef => volume_options[:imageref] }).body['volume']
        log(:info, "Successfully created volume #{boot_index}: #{new_volume['id']}", true)
        volume_options[:uuid] = new_volume['id']
        created_volumes << new_volume['id']
      end
    end
    unless volume_hash.blank?
      if @task
        @task.set_option(:volume_hash, volume_hash)
        @task.set_option(:created_volumes, created_volumes)
        log(:info, "volume_hash: #{@task.options[:volume_hash].inspect}")
        log(:info, "created_volumes: #{@task.options[:created_volumes].inspect}")
      else
        $evm.set_state_var(:volume_hash, volume_hash)
        log(:info, "Workspace variable updated {:volume_hash=>#{$evm.get_state_var(:volume_hash)}}")
        $evm.set_state_var(:created_volumes, created_volumes)
        log(:info, "Workspace variable updated {:created_volumes=>#{$evm.get_state_var(:created_volumes)}}")
      end
    end
  end

  # Set Ruby rescue behavior
rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

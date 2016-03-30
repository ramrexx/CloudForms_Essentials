=begin
 rhev_add_disk_to_vm.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method is used to create volume(s) for RHEV VMs

 Input exmaple1: volume_1_size =>20, volume_1_storage_domain_id=>'6366a82a-8bf6-4ec4-93b5-19ede6e31d09', etc...
 Input exmaple2: volume_0_size =>10, volume_0_interface=>virtio_scsi, volume_0_bootable=>true, volume_0_activate=>true, etc...
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

def call_rhev(action, ref=nil, body_type=:json, body=nil)
  require 'rest_client'
  require 'json'

  servername = @vm.ext_management_system.hostname
  username   = @vm.ext_management_system.authentication_userid
  password   = @vm.ext_management_system.authentication_password

  unless ref.nil?
    url = ref if ref.include?('http')
  end
  url ||= "https://#{servername}"+"#{ref}"

  params = {
    :method=>action, :url=>url,:user=>username, :password=>password,
    :verify_ssl=>false, :headers=>{ :content_type=>body_type, :accept=>:json }
  }
  body_type == :json ? (params[:payload] = JSON.generate(body) if body) : (params[:payload] = body if body)
  log(:info, "Calling url: #{url} action: #{action} payload: #{params[:payload]}")

  response = RestClient::Request.new(params).execute
  log(:info, "response headers: #{response.headers.inspect}")
  log(:info, "response code: #{response.code}")
  log(:info, "response: #{response.inspect}")
  return JSON.parse(response) rescue (return response)
end


def get_storage_domain_id(volume_option, storage_domain_id=nil)
  storage_domain_id ||= volume_option[:storage_domain_id]
  storage_domain_id ||= @vm.storage.ems_ref.match(/.*\/(\w.*)$/)[1]
  return storage_domain_id
end

def get_size(volume_option, size=nil)
  return volume_option[:size] if volume_option[:size]
  return size
end

def get_type(volume_option, type='system')
  return volume_option[:type] if volume_option[:type]
  return 'system'
end

def get_interface(volume_option, interface='virtio')
  # possible values are [ide, virtio, virtio_scsi]
  return volume_option[:interface] if volume_option[:interface]
  return interface
end

def get_format(volume_option, format='cow')
  # possible values are [cow, raw]
  return volume_option[:format] if volume_option[:format]
  return format
end

begin
  $evm.root.attributes.sort.each { |k, v| log(:info, "$evm.root Attribute - #{k}: #{v}")}

  case $evm.root['vmdb_object_type']
  when 'miq_provision'
    @task = $evm.root['miq_provision']
    log(:info, "Task: #{@task.id} Request: #{@task.miq_request.id} Type:#{@task.type}")
    # get vm object from miq_provision. This assumes that the vm container on the management system is present
    @vm = @task.vm
  when 'vm'
    # get vm from root
    @vm = $evm.root['vm']
    log(:info, "VM: #{@vm.name} vendor: #{@vm.vendor}")
  else
    exit MIQ_OK
  end

  # get the volume options by parsing the @task options or by looking at $evm.root attributes
  volume_options_hash = get_volume_options_hash
  log(:info, "volume_options_hash: #{volume_options_hash}")
  exit MIQ_OK if volume_options_hash.blank?

  # get array_of_current_disks on the vm
  current_disks_hash = call_rhev(:get, "#{@vm.ems_ref}/disks")
  if current_disks_hash.blank?
    log(:info, "No disks found for VM: #{@vm.name}")
    array_of_current_disks = []
  else
    log(:info, "Disks found for VM: #{@vm.name} disks: #{current_disks_hash['disk']}")
    array_of_current_disks = current_disks_hash['disk']
  end
  number_of_current_disks = array_of_current_disks.count
  log(:info, "Number of current disks: #{number_of_current_disks}")

  # check to see if bootable disk already exists
  array_of_current_disks.each.detect { |disk| disk['bootable'].first =~ (/(true|t|yes|y|1)$/i) } ? @bootable_exists = true : @bootable_exists = false
  log(:info, "bootable_exists?: #{@bootable_exists}")

  created_volumes = []

  # loop through volume_options_hash
  volume_options_hash.each do |vol_index, volume_option|
    log(:info, "processing vol_index: #{vol_index} with volume_option: #{volume_option}")

    volume_option[:storage_domain_id] = get_storage_domain_id(volume_option)
    next if volume_option[:storage_domain_id].nil?

    volume_option[:size] = get_size(volume_option).to_i
    next if volume_option[:size].zero?
    volume_option[:size_in_bytes] = (volume_option[:size] * 1024**3)

    volume_option[:type] = get_type(volume_option)
    volume_option[:interface] = get_interface(volume_option)
    volume_option[:format] = get_format(volume_option)
    if @bootable_exists
      volume_option[:bootable] = false
    else
      volume_option[:bootable] = true
      @bootable_exists = true
    end

    body_hash = {
      "type"=>volume_option[:type],
      "size"=>volume_option[:size_in_bytes],
      "interface"=>volume_option[:interface],
      "format"=>volume_option[:format],
      "bootable"=>volume_option[:bootable],
      "storage_domain"=>{"id"=>volume_option[:storage_domain_id]}
    }

    log(:info, "Creating disk#: #{volume_option[:vol_index]} volume_options: #{volume_option}")
    create_disk_response_hash = call_rhev(:post, "#{@vm.ems_ref}/disks", :json, body_hash)
    log(:info, "create_disk_response_hash: #{create_disk_response_hash}")

    disk_id = create_disk_response_hash["id"]
    created_volumes << disk_id
    volume_option[:disk_id] = disk_id
    log(:info, "created_volumes: #{created_volumes}")
  end

  raise if created_volumes.blank?

  if @task
    @task.set_option(:created_volumes, created_volumes)
    log(:info, "Provisioning object updated {:created_volumes=>#{@task.options[:created_volumes]}}")
    @task.set_option(:volume_options_hash, volume_options_hash)
    log(:info, "Provisioning object updated {:volume_options_hash=>#{@task.options[:volume_options_hash]}}")
  end
  $evm.set_state_var(:created_volumes, created_volumes)
  log(:info, "Workspace variable updated {:created_volumes=>#{$evm.get_state_var(:created_volumes)}}")
  $evm.set_state_var(:volume_options_hash, volume_options_hash)
  log(:info, "Workspace variable updated {:volume_options_hash=>#{$evm.get_state_var(:volume_options_hash)}}")

rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

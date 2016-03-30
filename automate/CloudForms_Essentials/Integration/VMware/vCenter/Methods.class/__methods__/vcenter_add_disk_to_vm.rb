=begin
  vcenter_add_disk_to_vm.rb

  Author: Kevin Morey <kevin@redhat.com>

  Description: This method is used to add a new disk to an existing VM running on VMware

  Input exmaple1: volume_1_size =>20, volume_2_size=30

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

def get_size(volume_option, size=nil)
  return volume_option[:size] if volume_option[:size]
  return size
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

  # loop through volume_options_hash
  volume_options_hash.each do |vol_index, volume_option|
    log(:info, "processing vol_index: #{vol_index} with volume_option: #{volume_option}")

    volume_option[:size] = get_size(volume_option).to_i
    next if volume_option[:size].zero?

    volume_option[:size_in_megabytes] = (volume_option[:size] * 1024)

    # Get the vimVm object
    vim_vm = @vm.object_send('instance_eval', 'with_provider_object { | vimVm | return vimVm }')

    # Add disk to a VM
    log(:info, "Creating a new #{volume_option[:size]}GB disk on Storage: #{@vm.storage_name}")
    vim_vm.addDisk("[#{@vm.storage_name}]", volume_option[:size_in_megabytes])
    sleep 10
  end

rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

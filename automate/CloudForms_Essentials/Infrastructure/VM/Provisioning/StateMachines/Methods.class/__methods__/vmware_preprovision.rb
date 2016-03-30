=begin
 vmware_preprovision.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method is used to apply PreProvision customizations during
   VMware provisioning
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

def set_network
  log(:info, "Processing set_vlan...", true)
  # Was a VLAN selected in dialog? If not you can set one here
  if @task.get_option(:vlan).nil?
    default_vlan = "VM Network"
    #default_dvs = "portgroup1"
    @task.set_vlan(default_vlan)
    #@task.set_dvs(default_dvs)
    log(:info, "Provisioning object <:vlan> updated with <#{@task.get_option(:vlan)}>")
  end
  log(:info, "Processing set_vlan...Complete", true)
end

def set_folder
  log(:info, "Processing set_folder...", true)
  ###################################
  # Drop the VM in the targeted folder if no folder was chosen in the dialog
  # The vCenter folder must exist for the VM to be placed correctly else the
  # VM will placed along with the template
  # Folder starts at the Data Center level
  ###################################
  if @task.get_option(:placement_folder_name).nil?
    datacenter = @template.v_owning_datacenter
    vsphere_fully_qualified_folder = "#{datacenter}/Discovered virtual machine"

    # @task.get_folder_paths.each { |key, path| log(:info, "Eligible folders:<#{key.inspect}> - <#{path.inspect}>") }
    @task.set_folder(vsphere_fully_qualified_folder)
    log(:info, "Provisioning object <:placement_folder_name> updated with <#{@task.options[:placement_folder_name].inspect}>")
  else
    log(:info, "Placing VM in folder: <#{@task.options[:placement_folder_name].inspect}>")
  end
  log(:info, "Processing set_folder...Complete", true)
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
  end
  volume_options_hash
end

def get_size(volume_option, size=nil)
  return volume_option[:size] if volume_option[:size]
  return size
end

# add_disk - look in ws_values and @task.options for volume_(\d) parameters
def add_volumes
  log(:info, "Processing add_volumes...", true)
  # get the volume options by parsing the @task options or by looking at $evm.root attributes
  volume_options_hash = get_volume_options_hash
  log(:info, "volume_options_hash: #{volume_options_hash}")
  return if volume_options_hash.blank?

  new_disks = []

  # loop through volume_options_hash
  volume_options_hash.each do |vol_index, volume_option|
    log(:info, "processing vol_index: #{vol_index} with volume_option: #{volume_option}")

    volume_option[:size] = get_size(volume_option).to_i
    next if volume_option[:size].zero?

    volume_option[:size_in_megabytes] = (volume_option[:size] * 1024)
    scsi_start_idx = 2
    new_disks << {:bus=>0, :pos=>(scsi_start_idx + vol_index), :sizeInMB=> volume_option[:size_in_megabytes]}
    @task.set_option(:disk_scsi, new_disks) unless new_disks.blank?
    log(:info, "Provisioning object <:disk_scsi> updated with <#{@task.get_option(:disk_scsi)}>")
  end
  log(:info, "Processing add_volumes...Complete", true)
end

def set_resource_pool
  log(:info, "Processing set_resource_pool...", true)
  if @task.get_option(:placement_rp_name).nil?
    ############################################
    # Find and set the Resource Pool for a VM:
    ############################################
    default_resource_pool = 'MyResPool'
    respool = @task.eligible_resource_pools.detect { |c| c.name.casecmp(default_resource_pool) == 0 }
    if respool
      log(:info, "Provisioning object updated {:placement_rp_name=>#{respool.name.inspect}}")
      @task.set_resource_pool(respool)
    end
  end
  log(:info, "Processing set_resource_pool...Complete", true)
end

def set_description
  log(:info, "Processing set_notes...", true)
  ###################################
  # Set the VM Description and VM Annotations  as follows:
  # The example would allow user input in provisioning dialog "vm_description"
  # to be added to the VM notes
  ###################################
  # Stamp VM with custom description
  unless @task.get_option(:vm_description).nil?
    vmdescription = @task.get_option(:vm_description)
    @task.set_option(:vm_description, vmdescription)
    log(:info, "Provisioning object {:vmdescription=>#{@task.get_option(:vm_description)}}")
  end
end

def set_notes
  # Setup VM Annotations
  vm_notes =  "Owner: #{@task.get_option(:owner_first_name)} #{@task.get_option(:owner_last_name)}"
  vm_notes += "\nEmail: #{@task.get_option(:owner_email)}"
  vm_notes += "\nSource: #{@template.name}"
  vm_notes += "\nDescription: #{@task.get_option(:vm_description)}" unless @task.get_option(:vm_description).nil?
  @task.set_vm_notes(vm_notes)
  log(:info, "Provisioning object <:vm_notes> updated with <#{vm_notes}>")
  log(:info, "Processing set_notes...Complete", true)
end

begin
  # Get provisioning object
  @task = $evm.root['miq_provision']
  log(:info, "Provision:<#{@task.id}> Request:<#{@task.miq_request.id}> Type:<#{@task.type}>")

  @template = @task.vm_template
  provider = @template.ext_management_system
  product  = @template.operating_system['product_name'].downcase
  bitness = @template.operating_system['bitness']
  log(:info, "Template:<#{@template.name}> Provider:<#{provider.name}> Vendor:<#{@template.vendor}> Product:<#{product}> Bitness:<#{bitness}>")

  tags = @task.get_tags
  log(:info, "Provision Tags:<#{tags.inspect}>")

  set_resource_pool

  set_folder

  set_network

  set_description

  set_notes

  add_volumes

  # Set Ruby rescue behavior
rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_STOP
end

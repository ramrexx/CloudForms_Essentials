=begin
 redhat_preprovision.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method is used to apply PreProvision customizations 
    during RHEV provisioning
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
  $evm.root['miq_provision'].message = "#{msg}" if $evm.root['miq_provision'] && update_message
end

def process_customization(prov)
  # Choose the sections to process
  set_vlan  = false
  set_notes = true

  # Get information from the template platform
  template = prov.vm_template
  product  = template.operating_system['product_name'].downcase
  log(:info, "Template:<#{template.name}> Vendor:<#{template.vendor}> Product:<#{product}>")

  if set_vlan
    # Set default VLAN here if one was not chosen in the dialog?
    default_vlan = "rhevm"

    if prov.get_option(:vlan).nil?
      prov.set_vlan(default_vlan)
      log(:info, "Provisioning object <:vlan> updated with <#{default_vlan}>")
    end
  end

  if set_notes
    log(:info, "Processing set_notes...", true)
    ###################################
    # Set the VM Description and VM Annotations  as follows:
    # The example would allow user input in provisioning dialog "vm_description"
    # to be added to the VM notes
    ###################################
    # Stamp VM with custom description
    unless prov.get_option(:vm_description).nil?
      vmdescription = prov.get_option(:vm_description)
      prov.set_option(:vm_description, vmdescription)
      log(:info, "Provisioning object <:vmdescription> updated with <#{vmdescription}>")
    end

    # Setup VM Annotations
    vm_notes =  "Owner: #{prov.get_option(:owner_first_name)} #{prov.get_option(:owner_last_name)}"
    vm_notes += "\nEmail: #{prov.get_option(:owner_email)}"
    vm_notes += "\nSource Template: #{template.name}"
    vm_notes += "\nCustom Description: #{vmdescription}" unless vmdescription.nil?
    prov.set_vm_notes(vm_notes)
    log(:info, "Provisioning object <:vm_notes> updated with <#{vm_notes}>")
    log(:info, "Processing set_notes...Complete", true)
  end
end

begin

  # Get provisioning object
  prov = $evm.root['miq_provision']
  log(:info, "Provision:<#{prov.id}> Request:<#{prov.miq_provision_request.id}> Type:<#{prov.type}>")

  process_customization(prov)

rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

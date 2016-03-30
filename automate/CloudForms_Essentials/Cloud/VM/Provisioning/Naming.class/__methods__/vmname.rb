=begin
  vmname.rb

  Author: Kevin Morey <kevin@redhat.com>

  Description: The method overrides the default vm naming method
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

begin
  @task = $evm.root['miq_provision_request'] || $evm.root['miq_provision'] || $evm.root['miq_provision_request_template']

  vm_name = @task.get_option(:vm_name).to_s.strip
  number_of_vms_being_provisioned = @task.get_option(:number_of_vms)
  dialog_vm_prefix = @task.get_option(:vm_prefix).to_s.strip

  product  = @task.vm_template.operating_system['product_name'].downcase rescue 'other'

  if product.include?('red hat')
    os_prefix = 'r'
  elsif product.include?('suse')
    os_prefix = 's'
  elsif product.include?('windows')
    os_prefix = 'w'
  elsif product.include?('other')
    os_prefix = 'o'
  elsif product.include?('linux')
    os_prefix = 'l'
  else
    os_prefix = nil
  end
  log(:info, "vm_name: #{vm_name} template: #{@task.vm_template.name} product: #{product} os_prefix: #{os_prefix}")

  # If no VM name was chosen during dialog
  if vm_name.blank? || vm_name == 'changeme'
    vm_prefix = nil
    vm_prefix ||= $evm.object['vm_prefix']
    log("info", "vm_name from dialog: #{vm_name.inspect} vm_prefix from dialog: #{dialog_vm_prefix.inspect} vm_prefix from model: #{vm_prefix.inspect}")

    # Get Provisioning Tags for VM Name
    tags = @task.get_tags
    log(:info, "Provisioning Object Tags: #{tags.inspect}")

    # Set a Prefix for VM Naming
    dialog_vm_prefix.blank? ? vm_name = $evm.object['vm_prefix'] : vm_name = dialog_vm_prefix

    log("info", "VM Naming Prefix: #{vm_name}")

    # case environment tag
    case tags[:environment]
    when 'test'
      env_name = 'tst'
    when 'prod'
      env_name = 'prd'
    when 'dev'
      env_name = 'dev'
    when 'qa'
      env_name = 'qa'
    else
      env_name = nil
    end
    derived_name = "#{vm_name}#{env_name}#{os_prefix}$n{3}"
  else
    if number_of_vms_being_provisioned == 1
      derived_name = "#{vm_name}"
    else
      derived_name = "#{vm_name}$n{3}"
    end
  end

  $evm.object['vmname'] = derived_name
  log(:info, "VM Name: #{derived_name}")

rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

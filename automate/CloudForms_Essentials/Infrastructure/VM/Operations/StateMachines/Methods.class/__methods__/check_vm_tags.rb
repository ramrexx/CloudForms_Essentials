=begin
 check_vm_tags.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method checks for rightsize tag and stops the VM
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

  category = :rightsize

  vm = $evm.root['vm']
  raise "VM not found" if vm.nil?
  log(:info, "Found VM: #{vm.name} vendor: #{vm.vendor} tags: #{vm.tags}")

  raise "Invalid vendor: #{vm.vendor}" unless vm.vendor.downcase == 'vmware'

  rightsizing = vm.tags(category).first rescue nil
  raise "VM: #{vm.name} is not tagged with #{category}" if rightsizing.nil?

  if vm.power_state == 'on'
    log(:info, "Stopping VM: #{vm.name}")
    vm.stop
  end

rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

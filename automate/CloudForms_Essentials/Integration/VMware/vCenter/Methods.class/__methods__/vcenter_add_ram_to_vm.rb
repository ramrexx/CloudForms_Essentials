=begin
  vcenter_add_ram_to_vm.rb

  Author: Kevin Morey <kevin@redhat.com>

  Description: This method is used to modify vRAM to an existing VM running on VMware

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

# Get vm object from root
vm = $evm.root['vm']
raise "Missing $evm.root['vm'] object" if vm.nil?

# if dialog_ram then we are adding ram
ram = $evm.root['dialog_ram'].to_i

unless ram.zero?
  log(:info, "Adding #{ram} MB to VM: #{vm.name} current memory: #{vm.mem_cpu}")
  ram += vm.mem_cpu 
end

ram = $evm.root['dialog_vm_memory'].to_i if ram.zero?

unless ram.zero?
  log(:info, "Setting VM: #{vm.name} vRAM to: #{ram}")
  vm.set_memory(ram, :sync => true)
end

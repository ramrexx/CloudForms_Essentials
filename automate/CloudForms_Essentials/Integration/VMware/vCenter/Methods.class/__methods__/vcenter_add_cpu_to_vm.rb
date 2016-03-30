=begin
  vcenter_add_cpu_to_vm.rb

  Author: Kevin Morey <kevin@redhat.com>

  Description: This method is used to modify vCPUs to an existing VM running on VMware

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

# Check to ensure that the VM in question is vmware
vendor = vm.vendor.downcase rescue nil
raise "Invalid vendor detected: #{vendor}" unless vendor == 'vmware'

# if dialog_cpus then we are adding cpus
vcpus = $evm.root['dialog_cpus'].to_i

unless vcpus.zero?
  log(:info, "Adding #{vcpus} vCPU(s) to VM: #{vm.name} current vCPU count: #{vm.num_cpu}")
  vcpus += vm.num_cpu 
end

vcpus = $evm.root['dialog_cores_per_socket'].to_i if vcpus.zero?

unless vcpus.zero?
  log(:info, "Setting VM: #{vm.name} vCPU count to: #{vcpus}")
  vm.set_number_of_cpus(vcpus, :sync=>true)
end

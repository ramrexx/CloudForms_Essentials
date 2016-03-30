=begin
list_vcenter_vm_disk_numbers.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: List the disk numbers on a VM
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

$evm.root.attributes.sort.each { |k, v| log(:info, "\t Attribute: #{k} = #{v}")}

# Get vm object from root
vm = $evm.root['vm']

dialog_hash = {}

# get current number of hard drives
num_disks = vm.num_hard_disks

for disk_num in (1..num_disks)
  disk_size = "disk_#{disk_num}_size"
  if vm.respond_to?(disk_size)
    dialog_hash[disk_num] = "disk#{disk_num}" unless vm.send(disk_size).to_i.zero?
  end
end

if dialog_hash.blank?
  dialog_hash[''] = "< No disks found >"
else
  $evm.object['default_value'] = dialog_hash.first[0]
end

$evm.object['values'] = dialog_hash
log(:info, "Dialog Values: #{$evm.object['values'].inspect}")

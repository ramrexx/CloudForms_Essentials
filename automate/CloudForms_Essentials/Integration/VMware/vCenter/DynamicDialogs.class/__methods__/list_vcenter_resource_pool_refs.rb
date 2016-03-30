=begin
list_vcenter_resource_pool_refs.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: List the resource pools associated with a provider
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
raise "Missing $evm.root['vm'] object" if vm.nil?

provider = vm.ext_management_system
log(:info, "Detected Provider: #{provider.name}")

dialog_hash = {}

provider.resource_pools.each do |pool|
  log(:info, "Looking at resource_pool: #{pool.name} id: #{pool.id} ems_ref: #{pool.ems_ref}")
  if vm.resource_pool && vm.resource_pool.ems_ref == pool.ems_ref
    dialog_hash[pool[:ems_ref]] = "<current> #{pool[:name]}"
  else
    dialog_hash[pool[:ems_ref]] = pool[:name]
  end
end

if dialog_hash.blank?
  dialog_hash[''] = "< No resource_pools found >"
else
  $evm.object['default_value'] = dialog_hash.first[0]
end

$evm.object['values'] = dialog_hash
log(:info, "Dialog Values: #{$evm.object['values'].inspect}")

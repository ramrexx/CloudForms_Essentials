=begin
list_vcenter_datastore_refs.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: List the datastore refs associated with a provider
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

provider = vm.ext_management_system
log(:info, "Detected Provider: #{provider.name}")

dialog_hash = {}

provider.storages.each do |storage|
  #next unless template.tagged_with?('prov_scope', 'all')
  #next unless template.vendor.downcase == 'vmware'
  if vm.storage.ems_ref == storage.ems_ref
    dialog_hash[storage[:ems_ref]] = "<current> #{storage[:name]}"
  else
    dialog_hash[storage[:ems_ref]] = storage[:name]
  end
end

if dialog_hash.blank?
  dialog_hash[''] = "< No datastores found >"
else
  $evm.object['default_value'] = dialog_hash.first[0]
end

$evm.object['values'] = dialog_hash
log(:info, "Dialog Values: #{$evm.object['values'].inspect}")

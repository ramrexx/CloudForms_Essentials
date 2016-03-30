=begin
  list_openstack_flavors_for_vm_ids.rb

  Author: Kevin Morey <kmorey@redhat.com>

  Description: List available OpenStack flavor ids for a particular instance's provider

-------------------------------------------------------------------------------
   Copyright 2016 Kevin Morey <kmorey@redhat.com>

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

def dump_root()
  log(:info, "Begin $evm.root.attributes")
  $evm.root.attributes.sort.each { |k, v| log(:info, "\t Attribute: #{k} = #{v}")}
  log(:info, "End $evm.root.attributes")
  log(:info, "")
end

###############
# Start Method
###############
log(:info, "CloudForms Automate Method Started", true)
dump_root()
vm = $evm.root['vm']
vm_flavor_id = vm.flavor.id

dialog_hash = {}
provider = vm.ext_management_system

provider.flavors.each do |fl|
  log(:info, "Looking at flavor: #{fl.name} id: #{fl.id} cpus: #{fl.cpus} memory: #{fl.memory} ems_ref: #{fl.ems_ref}")
  next unless fl.ext_management_system || fl.enabled
  if fl.id == vm_flavor_id
    dialog_hash[''] = "<Current - #{fl.name}>"
  else
    dialog_hash[fl.id] = "#{fl.name}"
  end
end

$evm.object["values"]     = dialog_hash
log(:info, "$evm.object['values']: #{$evm.object['values'].inspect}")

###############
# Exit Method
###############
log(:info, "CloudForms Automate Method Ended", true)
exit MIQ_OK

# Set Ruby rescue behavior
rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

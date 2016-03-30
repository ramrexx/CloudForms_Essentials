=begin
 list_service_vms.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method will build a list of vm ids attached to a service
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
  service  = $evm.root['service']
  log(:info, "Service: #{service.name} id: #{service.id} guid: #{service.guid} vms: #{service.vms.count}")

  dialog_hash = {}

  service.vms.each do |vm|
    if vm.archived?
      dialog_hash[vm.id] = "#{vm.name} [ARCHIVED] on #{service.name}"
    elsif vm.orphaned?
      dialog_hash[vm.id] = "#{vm.name} [ORPHANED] on #{service.name}"
    else
      dialog_hash[vm.id] = "#{vm.name} on #{service.name}"
    end
  end

  if dialog_hash.blank?
    log(:info, "No VMs found")
    dialog_hash[''] = "< No VMs found >"
  else
    dialog_hash[''] = dialog_hash.first[0]
  end

  $evm.object["values"]     = dialog_hash
  log(:info, "$evm.object['values']: #{$evm.object['values'].inspect}")

rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

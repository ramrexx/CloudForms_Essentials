=begin
 check_powered_off.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method checks to see if the VM has been powered off
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

  vm = $evm.root['vm']
  raise "VM not found" if vm.nil?
  log(:info, "VM: #{vm.name} vendor: #{vm.vendor} with power_state: #{vm.power_state} tags: #{vm.tags}")

  # If VM is powered off or suspended exit
  if vm.power_state == 'off'
    $evm.root['ae_result'] = 'ok'
  elsif vm.power_state == 'never' || vm.power_state == 'suspended'
    $evm.root['ae_result'] = 'error'
  else
    $evm.root['ae_result']         = 'retry'
    $evm.root['ae_retry_interval'] = '15.seconds'
  end

rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

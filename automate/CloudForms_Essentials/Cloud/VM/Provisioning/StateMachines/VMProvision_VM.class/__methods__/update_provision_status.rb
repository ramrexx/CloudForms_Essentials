=begin
 update_provision_status.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method upates the miq_request status
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
  @task   = $evm.root['miq_provision']

  ws_values = @task.options.fetch(:ws_values, {})
  log(:info, "WS Values: #{ws_values.inspect}") unless ws_values.blank?

  status = $evm.inputs['status']

  # build message string
  updated_message  = "#{$evm.root['miq_server'].name}: "
  updated_message += "VM: #{@task.get_option(:vm_target_name)} "
  updated_message += "Step: #{$evm.root['ae_state']} "
  updated_message += "Status: #{status} "
  updated_message += "Message: #{@task.message}"

  case $evm.root['ae_status_state']
  when 'on_entry'
    @task.miq_request.user_message = updated_message[0..250]
  when 'on_exit'
    @task.miq_request.user_message = updated_message[0..250]
  when 'on_error'
    @task.miq_request.user_message = updated_message[0..250]

    # email the requester with the provisioning failure details
    $evm.instantiate('/Infrastructure/VM/Provisioning/Email/MiqProvision_Failure')
  end

  # Set Ruby rescue behavior
rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_STOP
end

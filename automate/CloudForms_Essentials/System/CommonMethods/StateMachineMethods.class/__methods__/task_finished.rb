=begin
 task_finished.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method updates the final message(s) for the following 
    vmdb_object_types: ['service_template_provision_task', 'miq_provision']
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
  @task = $evm.root[$evm.root['vmdb_object_type']]

  # prefix the message with the appliance name (helpful in large environments)
  final_message = "#{$evm.root['miq_server'].name}: "

  case $evm.root['vmdb_object_type']
  when 'service_template_provision_task'
    final_message += "Service: #{@task.destination.name} Provisioned Successfully"
    unless @task.miq_request.get_option(:override_request_description).nil?
      @task.miq_request.description = @task.miq_request.get_option(:override_request_description)
    end
  when 'miq_provision'
    final_message += "VM: #{@task.get_option(:vm_target_name)} "
    final_message += "IP: #{@task.vm.ipaddresses.first} " if @task.vm && ! @task.vm.ipaddresses.blank?
    final_message += "Provisioned Successfully"
    override_request_description = @task.miq_request.get_option(:override_request_description) || ''
    override_request_description += "(#{final_message}) "
    @task.miq_request.set_option(:override_request_description, "#{override_request_description}")
  else
    final_message += $evm.inputs['message']
  end
  log(:info, "Final Message: #{final_message}", true)
  @task.miq_request.user_message = final_message
  @task.finished(final_message)

  # Set Ruby rescue behavior
rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_STOP
end

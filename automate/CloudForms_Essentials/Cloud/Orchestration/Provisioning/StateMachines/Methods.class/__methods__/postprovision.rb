=begin
  postprovision.rb

  Author: Nate Stephany <nate@redhat.com>

  Description: This is an extended preprovision method for deploying OpenStack
           Heat stacks. It will stamp the outputs of the Heat stack into the
           service and provisioning object options for future use.

  Mandatory dialog fields: NONE
-------------------------------------------------------------------------------
   Copyright 2016 Nate Stephany <nate@redhat.com>

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

def dump_stack_outputs(stack)
  log(:info, "Outputs from stack #{stack.name}")
  stack.outputs.each do |output|
    unless output.value.blank?
      @service.custom_set(output.key, output.value.to_s)
      @request.set_option(output.key, output.value)
      log(:info, "Key #{output.key}, value #{output.value}")
    end
  end
end

$evm.log("info", "Starting Orchestration Post-Provisioning")

@request = $evm.root["service_template_provision_task"].miq_request
@service = $evm.root["service_template_provision_task"].destination
stack = @service.orchestration_stack

dump_stack_outputs(stack)

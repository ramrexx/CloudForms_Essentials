=begin
 right_size_vm.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method reconfigures the VM based on right size recommendations
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

  category = :rightsize

  vm = $evm.root['vm']
  raise "VM not found" if vm.nil?
  log(:info, "Found VM: #{vm.name} tags: #{vm.tags} vCPUS: #{vm.num_cpu} vRAM: #{vm.mem_cpu}")

  rightsizing = vm.tags(category).first rescue nil
  raise "VM: #{vm.name} is not tagged with #{category}" if rightsizing.nil?

  case rightsizing
  when 'aggressive'
    recommended_cpu = vm.aggressive_recommended_vcpus.to_i
    recommended_mem = vm.aggressive_recommended_mem.to_i
  when 'moderate'
    recommended_cpu = vm.moderate_recommended_vcpus.to_i
    recommended_mem = vm.moderate_recommended_mem.to_i
  when 'conservative'
    recommended_cpu = vm.conservative_recommended_vcpus.to_i
    recommended_mem = vm.conservative_recommended_mem.to_i
  else
    raise "Missing rightsizing tag: #{rightsizing}"
  end

  unless recommended_cpu.zero?
    log(:info, "VM: #{vm.name} rightsizing: #{rightsizing} vCPUs: #{recommended_cpu}")
    vm.object_send('instance_eval', "with_provider_object { | vimVm | vimVm.setNumCPUs(#{recommended_cpu}) }")
  end

  unless recommended_mem.zero?
    log(:info, "VM: #{vm.name} rightsizing: #{rightsizing} vRAM: #{recommended_mem}")
    vm.object_send('instance_eval', "with_provider_object { | vimVm | vimVm.setMemory(#{recommended_mem}) }")
  end

rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

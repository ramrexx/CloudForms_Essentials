=begin
 vcenter_create_folder_check.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method checks to ensure that vcenter_folder_path has been created
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
def log(level, msg, update_message=false)
  $evm.log(level, "#{msg}")
  @task.message = msg if @task && (update_message || level == 'error')
end

def retry_method(retry_time=10.seconds, msg='INFO', update_message=false)
  log(:info, "#{msg} - retrying in #{retry_time} seconds}", update_message)
  $evm.root['ae_result'] = 'retry'
  $evm.root['ae_retry_interval'] = retry_time
  exit MIQ_OK
end

def get_task_option(task_option, result=nil)
  return nil unless @task
  ws_values = @task.options.fetch(:ws_values, {})
  result = ws_values[task_option.to_sym] || @task.get_option(task_option.to_sym)
  unless result.nil?
    log(:info, "Found task option: {#{task_option}=>#{result}}")
  end
  result
end

begin
  case $evm.root['vmdb_object_type']
  when 'miq_provision'
    @task = $evm.root['miq_provision']
    log(:info, "Task: #{@task.id} Request: #{@task.miq_provision_request.id} Type: #{@task.type}")
    unless @task.get_option(:placement_folder_name).nil?
      log(:info, "Provisioning object {:placement_folder_name=>#{@task.options[:placement_folder_name]}} already set")
      exit MIQ_OK
    end
    vm = prov.vm_template
  when 'vm'
    vm = $evm.root['vm']
  end

  if @task
    vcenter_folder_path = get_task_option(:vcenter_folder_path)
    vcenter_folder_path ||= $evm.root['dialog_vcenter_folder_path']
    vcenter_folder_path ||= $evm.object['vcenter_folder_path']

    unless vcenter_folder_path.blank?
      log(:info, "vcenter_folder_path: #{vcenter_folder_path}")
      vsphere_folder_path_obj = @task.get_folder_paths.detect {|key, path| vcenter_folder_path == path }
      unless vsphere_folder_path_obj.blank?
        @task.set_option(:placement_folder_name, vsphere_folder_path_obj)
        log(:info, "Provisioning object :placement_folder_name updated with #{@task.options[:placement_folder_name]}")
      else
        retry_method(15.seconds, "Waiting for vcenter_folder_path #{vcenter_folder_path} to be created", true )
      end
    end
  else
    # Waiting on BZ1302082 to get checked in before we can cleanly check folder path creation
    # so for now we are going to use the vm custom attribute
    vcenter_folder_path = vm.custom_get(:vcenter_folder_path)
    vcenter_folder_ref = vm.custom_get(:last_vcenter_folder_ref)
    log(:info, "vcenter_folder_path: #{vcenter_folder_path} \t vcenter_folder_ref: #{vcenter_folder_ref}")

    unless vcenter_folder_ref.nil?
      provder = vm.ext_management_system
      vsphere_folder_path_obj = provder.ems_folders.detect {|ef| ef[:ems_ref] == vcenter_folder_ref }
      if vsphere_folder_path_obj.nil?
        retry_method(15.seconds, "Waiting for vcenter_folder_path #{vcenter_folder_path} to be created" )
      else
        log(:info, "vcenter_folder_path: #{vcenter_folder_path} successfully created")
      end
    end
  end

rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

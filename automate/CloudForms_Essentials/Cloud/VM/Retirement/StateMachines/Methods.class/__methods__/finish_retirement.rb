=begin
 finish_retirement.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method marks the VM as retired and then removes the VM from 
  its service during retirement and for Flex VMs subtracts parent vm/service 
  tag :flex_current by 1
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

def process_tags(category, single_value, tag)
  # Convert to lower case and replace all non-word characters with underscores
  category_name = category.to_s.downcase.gsub(/\W/, '_')
  tag_name = tag.to_s.downcase.gsub(/\W/, '_')
  unless $evm.execute('category_exists?', category_name)
    log(:info, "Category #{category_name} doesn't exist, creating category")
    $evm.execute('category_create', :name => category_name, :single_value => single_value, :description => "#{category}")
  end
  unless $evm.execute('tag_exists?', category_name, tag_name)
    log(:info, "Adding new tag #{tag_name} in Category #{category_name}")
    $evm.execute('tag_create', category_name, :name => tag_name, :description => "#{tag}")
  end
end

def remove_vm_from_service
  return if @vm.service.nil?
  log(:info, "Removing VM: #{@vm.name} from Service: #{@vm.service.name}")
  @vm.remove_from_service
end

def process_flex
  parent_vm = $evm.vmdb(:vm).find_by_guid(@vm.custom_get(:flex_vm_guid))
  return if parent_vm.blank?
  log(:info, "Found flex parent_vm: #{parent_vm.name}")

  # Get the flex_current tag and convert it to an integer
  flex_current = parent_vm.tags(:flex_current).first.to_i

  return if flex_current.zero?

  # Decrease flex_current by 1
  new_serviceflex_current = flex_current - 1

  # Tag parent vm with new_serviceflex_current
  unless parent_vm.tagged_with?('flex_current', new_serviceflex_current)
    process_tags('flex_current', true, new_serviceflex_current)
    log(:info, "Assinging tag: {#{:flex_current}=>#{new_serviceflex_current}} to VM: #{parent_vm.name}")
    parent_vm.tag_assign("flex_current/#{new_serviceflex_current}")
  end
end

begin
  @vm = $evm.root['vm']
  exit MIQ_OK unless @vm

  @vm.finish_retirement

  remove_vm_from_service

  process_flex

rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_STOP
end

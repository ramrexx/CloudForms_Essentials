=begin
  list_openstack_heat_customization_template_ids.rb

  Author: David Costakos <dcostako@redhat.com>, Kevin Morey <kevin@redhat.com>

  Description: This method lists customization templates that contain the word heat
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

values_hash = {}

$evm.vmdb(:customization_template_cloud_init).all.each do |ct|
  if ct.name.downcase.includes?("heat")
    values_hash[ct.id] = ct.description
  end
end

$evm.object['default_value'] = values_hash.first[0]
$evm.object['values'] = values_hash
log(:info, "Dynamic drop down values: #{$evm.object['values']}")

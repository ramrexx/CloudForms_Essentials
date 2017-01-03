=begin
 list_rds_provider_ids.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method lists Amazon provider ids
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

$evm.root.attributes.sort.each { |k, v| log(:info, "\t Attribute: #{k} = #{v}")}

dialog_hash = {}

$evm.vmdb(:ManageIQ_Providers_Amazon_CloudManager).all.each do |provider|
  next unless provider.authentication_status == 'Valid'
  dialog_hash[provider.id] = "#{provider.name} - #{provider.provider_region}"
end

if dialog_hash.blank?
  dialog_hash[''] = "< no providers found >"
else
  $evm.object['default_value'] = dialog_hash.first[0]
end

$evm.object['values'] = dialog_hash
log(:info, "$evm.object['values']: #{$evm.object['values'].inspect}")

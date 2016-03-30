=begin
  list_vcenter_provider_ids.rb

  Author: Kevin Morey <kevin@redhat.com>

  Description: This method lists vCenter provider ids
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
$evm.root.attributes.sort.each { |k, v| $evm.log(:info, "\t Attribute: #{k} = #{v}")}

dialog_hash = {}

$evm.vmdb(:ManageIQ_Providers_Vmware_InfraManager).all.each do |provider|
  next if !provider.authentication_status == 'Valid'
  dialog_hash[provider.id] = "#{provider.name} in #{provider.provider_region}"
end

if dialog_hash.blank?
  dialog_hash[''] = "< No providers found >"
else
  $evm.object['default_value'] = dialog_hash.first[0]
end

$evm.object['values'] = dialog_hash
$evm.log(:info, "$evm.object['values']: #{$evm.object['values'].inspect}")

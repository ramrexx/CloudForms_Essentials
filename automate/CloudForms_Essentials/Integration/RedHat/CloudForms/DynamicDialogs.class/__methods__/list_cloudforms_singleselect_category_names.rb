=begin
 list_cloudforms_singleselect_category_names.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method lists CloudForms single-select Tag Category Names
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

$evm.vmdb('classification').all.each do |cat|
  next unless cat.parent_id.zero?
  next unless cat.single_value
    dialog_hash[cat.name] = "#{cat.name} - #{cat.description}"
end

if dialog_hash.blank?
  dialog_hash[''] = "< No single-select categories found >"
else
  $evm.object['default_value'] = dialog_hash.first[0]
end

$evm.object['values'] = dialog_hash
$evm.log(:info, "$evm.object['values']: #{$evm.object['values'].inspect}")

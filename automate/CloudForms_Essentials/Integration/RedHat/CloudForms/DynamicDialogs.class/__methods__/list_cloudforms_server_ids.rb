=begin
 list_cloudforms_server_ids.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method lists CloudForms server ids 
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

dialog_hash = {}

miq_servers = $evm.vmdb(:miq_server).all

miq_servers.each do |s|
  dialog_hash[s.id] = "server: #{s.name} id: #{s.id}"
end

choose = {''=>'< choose a miq_server id >'}
dialog_hash = choose.merge!(dialog_hash)

$evm.object["values"]     = dialog_hash
$evm.log(:info, "$evm.object['values']: #{$evm.object['values'].inspect}")

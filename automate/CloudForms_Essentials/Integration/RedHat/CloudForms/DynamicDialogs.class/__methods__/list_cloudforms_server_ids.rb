=begin
 list_cloudforms_server_ids.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method lists CloudForms server ids 
-------------------------------------------------------------------------------
   Copyright 2017 Kevin Morey <kevin@redhat.com>

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

def set_values_and_exit(dialog_hash)
  $evm.object["values"] = dialog_hash
  log(:info, "$evm.object['values']: #{$evm.object['values'].inspect}")
  $evm.object['default_value'] = dialog_hash.first[0]
end

dialog_hash = {}

$evm.vmdb(:miq_server).all.each do |server|
  dialog_hash[server.id] = "server: #{server.name} id: #{server.id}"
end

set_values_and_exit(dialog_hash)

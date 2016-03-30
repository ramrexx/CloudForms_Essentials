=begin
 quota_source.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method determines the quota source 
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

@miq_request = $evm.root['miq_request']
log(:info, "Request: #{@miq_request.description} id: #{@miq_request.id}")

# set the quota source type here [tenant, group, user]
$evm.root['quota_source_type'] = 'tenant'

case $evm.root['quota_source_type']
when 'tenant'
  $evm.root['quota_source'] = @miq_request.tenant
when 'group'
  $evm.root['quota_source'] = @miq_request.requester.current_group
when 'user'
  $evm.root['quota_source'] = @miq_request.requester
else
  $evm.root['quota_source_type'] = 'tenant'
  $evm.root['quota_source'] = @miq_request.tenant
end

log(:info, "Setting Quota Source ")

=begin
 list_rhev_vm_snapshot_uuids.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This is method builds a list of RHEV VM snapshot uuids
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

def call_rhev(action, ref=nil, body_type=:json, body=nil)
  require 'rest_client'
  require 'json'

  servername = @vm.ext_management_system.hostname
  username   = @vm.ext_management_system.authentication_userid
  password   = @vm.ext_management_system.authentication_password

  unless ref.nil?
    url = ref if ref.include?('http')
  end
  url ||= "https://#{servername}"+"#{ref}"

  params = {
    :method=>action, :url=>url,:user=>username, :password=>password,
    :verify_ssl=>false, :headers=>{ :content_type=>body_type, :accept=>:json }
  }
  body_type == :json ? (params[:payload] = JSON.generate(body) if body) : (params[:payload] = body if body)
  log(:info, "Calling url: #{url} action: #{action} payload: #{params[:payload]}")

  response = RestClient::Request.new(params).execute
  log(:info, "response headers: #{response.headers.inspect}")
  log(:info, "response code: #{response.code}")
  log(:info, "response: #{response.inspect}")
  return JSON.parse(response) rescue (return response)
end

$evm.root.attributes.sort.each { |k, v| log(:info, "\t $evm.root Attribute - #{k}: #{v}")}

@vm = $evm.root['vm']

list_snapshot_response_hash = call_rhev(:get, "#{@vm['ems_ref']}/snapshots/")
log(:info, "list_snapshot_response_hash: #{list_snapshot_response_hash}")

snapshots_array = list_snapshot_response_hash['snapshot']

dialog_hash={}
snapshots_array.each do |ss|
  next if snapshot_locked
  log(:info, "snapshot: #{ss["description"]} type: #{ss['type']}")
  description = "#{ss['description']}"
  if ss['type'] == 'active'
    description += " - (current)"
  end
  description += " - [#{ss['snapshot_status']}]"
  dialog_hash[ss['id']] = description
end

$evm.object["values"]     = dialog_hash
log(:info, "$evm.object['values']: #{$evm.object['values'].inspect}")

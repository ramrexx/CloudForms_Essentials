=begin
 rhev_revert_snapshot.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This is method reverts a snapshot for RHEV VM
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

begin

  $evm.root.attributes.sort.each { |k, v| log(:info, "\t $evm.root Attribute - #{k}: #{v}")}

  @vm = $evm.root['vm']

  snapshot_ref = $evm.root["dialog_snapshot_ref"]

  reverted_snapshots = []

  exit MIQ_OK if snapshot_ref.blank?

  log(:info, "Found vm: #{@vm.name} uuid: #{@vm['uid_ems']} snapshot_ref: #{snapshot_ref}")

  revert_snapshot_response_hash = call_rhev(:post, "#{snapshot_ref}/restore")
  log(:info, "revert_snapshot_response_hash: #{revert_snapshot_response_hash}")
  reverted_snapshots << revert_snapshot_response_hash['href']
  snapshot_staus = revert_snapshot_response_hash["snapshot_status"]
  snapshot_description = revert_snapshot_response_hash["description"]

  log(:info, "Snapshot: #{snapshot_description} status: #{snapshot_staus}")

  $evm.set_state_var(:snapshot_description, snapshot_description)
  log(:info, "Workspace variable updated {:snapshot_description=>#{$evm.get_state_var(:snapshot_description)}}")
  $evm.set_state_var(:reverted_snapshots, reverted_snapshots)
  log(:info, "Workspace variable updated {:reverted_snapshots=>#{$evm.get_state_var(:deleted_snapshots)}}")

  @vm.custom_set(:SNAPSHOT_REVERT_STATUS, snapshot_staus)

rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

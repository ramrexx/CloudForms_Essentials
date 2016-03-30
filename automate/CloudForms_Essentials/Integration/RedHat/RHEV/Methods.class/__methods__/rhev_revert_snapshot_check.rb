=begin
 rhev_revert_snapshot_check.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This is method checks that snapshots identified in $evm.get_state_var(:reverted_snapshots)
    have been reverted in RHEV
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

  snapshot_description = $evm.get_state_var(:snapshot_description)
  log(:info, "{:snapshot_description=>#{snapshot_description}}")

  reverted_snapshots = $evm.get_state_var(:reverted_snapshots)
  log(:info, "{:reverted_snapshots=>#{reverted_snapshots}}")

  reverted_snapshots.each do |snapshot_ref|
    log(:info, "Checking status for snapshot: #{snapshot_description} ")

    check_status_response_hash = call_rhev(:get, snapshot_ref)

    log(:info, "check_status_response_hash: #{check_status_response_hash}")
    snapshot_staus = check_status_response_hash["snapshot_status"]

    if snapshot_staus == 'ok'
      log(:info, "Successfully reverted snapshot: #{snapshot_description} snapshot_staus: #{snapshot_staus}", true)
      @vm.custom_set(:SNAPSHOT_REVERT_STATUS, nil)
    else
      @vm.custom_set(:SNAPSHOT_REVERT_STATUS, snapshot_staus)
      retry_method('30.seconds', "snapshot_description: #{snapshot_description} snapshot_staus: #{snapshot_staus}")
    end
  end

  # Ruby rescue
rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

=begin
 rhev_delete_snapshot_check.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This is method checks that snapshots identified in $evm.get_state_var(:deleted_snapshots)
              have been deleted in RHEV
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

def retry_method(retry_time='1.minute', msg='RETRYING', update_message=false)
  log(:info, "#{msg} - retrying in #{retry_time}}", update_message)
  $evm.root['ae_result'] = 'retry'
  $evm.root['ae_retry_interval'] = retry_time
  exit MIQ_OK
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

  case $evm.root['vmdb_object_type']
  when 'vm'
    # get vm from root
    @vm = $evm.root['vm']
  else
    exit MIQ_OK
  end

  deleted_snapshots = $evm.get_state_var(:deleted_snapshots)
  log(:info, "{:deleted_snapshots=>#{deleted_snapshots}}")

  deleted_snapshots.each do |snapshot_ref|
    log(:info, "Checking status for snapshot_ref: #{snapshot_ref} ")

    list_snapshot_response_hash = call_rhev(:get, "#{@vm['ems_ref']}/snapshots/")
    log(:info, "list_snapshot_response_hash: #{list_snapshot_response_hash}")

    snapshots_array = list_snapshot_response_hash['snapshot']

    snapshot_hash = snapshots_array.detect {|ss| ss['href'] == snapshot_ref }

    unless snapshot_hash.blank?
      snapshot_status = snapshot_hash["snapshot_status"]
      log(:info, "snapshot_status: #{snapshot_status}")
    else
      snapshot_status = 'ok'
    end

    if snapshot_status == 'ok'
      log(:info, "Successfully deleted snapshot", true)
      @vm.custom_set(:SNAPSHOT_DELETE_STATUS, nil)
    else
      @vm.custom_set(:SNAPSHOT_DELETE_STATUS, snapshot_status)
      retry_method('90.seconds', "snapshot_status: #{snapshot_status}")
    end
  end

  # Ruby rescue
rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

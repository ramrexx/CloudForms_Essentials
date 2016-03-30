=begin
 rhev_create_snapshot.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This is method creates a snapshot for a RHEV VM
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

  case $evm.root['vmdb_object_type']
  when 'miq_provision'
    @task = $evm.root['miq_provision']
    log(:info, "Task: #{@task.id} Request: #{@task.miq_request.id} Type:#{@task.type}")
    ws_values = @task.options.fetch(:ws_values, {})
    @vm = @task.vm
    snapshot_description = ws_values[:snapshot_description] || @task.get_option(:snapshot_description)
  when 'vm'
    # get vm from root
    @vm = $evm.root['vm']
    snapshot_description = $evm.root["dialog_snapshot_description"]
  else
    exit MIQ_OK
  end

  created_snapshots = []

  if snapshot_description.blank?
    snapshot_description = "Snapshot #{Time.now.strftime('%C%y%m%d-%H%M%S')}"
  end

  log(:info, "Found vm: #{@vm.name} uuid: #{@vm['uid_ems']} snapshot_description: #{snapshot_description}")

  body_hash = { :description => snapshot_description }

  create_snapshot_response_hash = call_rhev(:post, "#{@vm['ems_ref']}/snapshots/", :json, body_hash)
  log(:info, "create_snapshot_response_hash: #{create_snapshot_response_hash}")
  created_snapshots << create_snapshot_response_hash['href']
  snapshot_status = create_snapshot_response_hash["snapshot_status"]

  log(:info, "snapshot_description: #{snapshot_description} snapshot_status: #{snapshot_status}")

  $evm.set_state_var(:snapshot_description, snapshot_description)
  log(:info, "Workspace variable updated {:snapshot_description=>#{$evm.get_state_var(:snapshot_description)}}")
  $evm.set_state_var(:created_snapshots, created_snapshots)
  log(:info, "Workspace variable updated {:created_snapshots=>#{$evm.get_state_var(:created_snapshots)}}")

  @vm.custom_set(:SNAPSHOT_CREATE_STATUS, snapshot_status)

  # Ruby rescue
rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

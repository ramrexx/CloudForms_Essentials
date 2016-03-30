=begin
 rhev_add_disk_to_vm_check.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: his method checks that disks identified in $evm.get_state_var(:created_volumes)
              have been created in RHEV
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

def retry_method(retry_time='1.minute', msg='RETRYING')
  log(:info, "#{msg} - retrying in #{retry_time}}", true)
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
  $evm.root.attributes.sort.each { |k, v| log(:info, "Root:<$evm.root> Attribute - #{k}: #{v}")}

  created_volumes = $evm.get_state_var(:created_volumes)
  volume_options_hash = $evm.get_state_var(:volume_options_hash)

  case $evm.root['vmdb_object_type']

  when 'miq_provision'
    @task = $evm.root['miq_provision']
    ws_values = @task.options.fetch(:ws_values, {})
    log(:info, "Task: #{@task.id} Request: #{@task.miq_request.id} Type:#{@task.type}")
    @vm = @task.vm
    created_volumes ||= ws_values[:created_volumes] || @task.get_option(:created_volumes)
    volume_options_hash ||= ws_values[:volume_options_hash] || @task.get_option(:volume_options_hash)
  when 'vm'
    @vm = $evm.root['vm']
  end

  log(:info, "{:created_volumes=>#{created_volumes}}")
  log(:info, "{:volume_options_hash=>#{volume_options_hash}}")

  exit MIQ_OK if created_volumes.blank? || @vm.nil?

  # loop through created_volumes
  created_volumes.each do |disk_id|
    log(:info, "Checking status for disk: #{disk_id}")

    check_status_response_hash = call_rhev(:get, "#{@vm.ems_ref}/disks/#{disk_id}")

    # log(:info, "check_status_response_hash: #{check_status_response_hash}")
    active = check_status_response_hash["active"]
    status = check_status_response_hash["status"]["state"]
    if status == 'ok'
      if active == 'true'
        log(:info, "Successfully created disk: #{disk_id} status: #{status} active: #{active}")
      else
        call_rhev(:post, "#{@vm.ems_ref}/disks/#{disk_id}/activate")
        retry_method('30.seconds', "disk: #{disk_id} active: #{active}")
      end
    else
      retry_method('30.seconds', "disk: #{disk_id} status: #{status}")
    end
  end

  # Comment the following if you DO NOT want the vm to startup after the disks have been created and activated
  if @task
    log(:info, "Powering on VM: #{@vm.name}", true)
    if @vm.power_state == 'off'
      @vm.start
    end
  end

rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

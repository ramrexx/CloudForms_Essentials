=begin
 rhev_add_comments_to_vm.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method updates the VM description/comments in RHEVM 
    and can either be called via a button or during provisioning
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

  begin
    response = RestClient::Request.new(params).execute
  rescue => resterr
    log(:info, "resterr: #{resterr.inspect}")
    log(:info, "response: #{response.inspect}")
  end

  log(:info, "response headers: #{response.headers}")
  log(:info, "response code: #{response.code}")
  log(:info, "response: #{response.inspect}")
  return JSON.parse(response) rescue (return response)
end

begin
  $evm.root.attributes.sort.each { |k, v| log(:info, "$evm.root Attribute - #{k}: #{v}")}

  case $evm.root['vmdb_object_type']

  when 'miq_provision'
    @task = $evm.root['miq_provision']
    log(:info, "Provision:<#{@task.id}> Request:<#{@task.miq_provision_request.id}> Type:<#{@task.type}>")

    # get vm object from miq_provision. This assumes that the vm container on the management system is present
    @vm = @task.vm

    # Since this is provisioning we need to put in retry logic to wait the vm is present
    retry_method() if @vm.nil?

    unless @task.get_option(:vm_notes).nil?
      description = @task.get_option(:vm_notes)
    else
      # Setup VM Notes & Annotations
      description =  "Owner: #{@task.get_option(:owner_first_name)} #{@task.get_option(:owner_last_name)}"
      description += "\nEmail: #{@task.get_option(:owner_email)}"
      description += "\nSource Template: #{@task.vm_template.name}"
      description += "\nCustom Description: #{@task.get_option(:vm_description)}" unless @task.get_option(:vm_description).nil?
    end

  when 'vm'
    # get vm from root
    @vm = $evm.root['vm']

    # get description from button/service dialog
    description = $evm.root['dialog_description']
  end

  if @vm && @vm.vendor.downcase == 'redhat'
    log(:info, "Found VM: #{@vm.name} vendor: #{@vm.vendor.downcase}")
    body_hash = {
      "description"=>description,
      # "comment"=>'mycomment12'
    }
    call_rhev(:put, @vm.ems_ref, :json, body_hash)
    @vm.custom_set(:comments_added, 'true')
  end

rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

=begin
 rhev_host_activation.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method activates a host in maintenance mode
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

def call_rhev(action, ref=nil, body_type=:xml, body=nil)
  require 'rest_client'
  require 'json'

  servername = @host.ext_management_system.hostname
  username   = @host.ext_management_system.authentication_userid
  password   = @host.ext_management_system.authentication_password

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

  case $evm.root['vmdb_object_type']
  when 'host'
    # get host from root
    @host = $evm.root['host']
    log(:info, "Activating host:#{@host.name}")
    response = call_rhev(:post, "#{@host.ems_ref}/activate", :xml, '<action></action>')
    log(:info, "response: #{response.inspect}")
  else
    exit MIQ_OK
  end

rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

=begin
  openstack_detach_interface.rb

  Author: Dave Costakos <david.costakos@redhat.com>

  Description: Detach an interface from a VM
-------------------------------------------------------------------------------
   Copyright 2016 Dave Costakos <david.costakos@redhat.com>

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

def dump_root()
  log(:info, "Begin $evm.root.attributes")
  $evm.root.attributes.sort.each { |k, v| log(:info, "\t Attribute: #{k} = #{v}")}
  log(:info, "End $evm.root.attributes")
  log(:info, "")
end

def set_ae_options_hash(hash)
  log(:info, "Adding {#{hash}} to ae_workspace: #{@ae_state_var}", true)
  $evm.set_state_var(@state_var, hash)
end

def get_fog_object(type='Compute', tenant='admin', endpoint='adminURL')
  require 'fog/openstack'
  (@provider.api_version == 'v2') ? (conn_ref = '/v2.0/tokens') : (conn_ref = '/v3/auth/tokens')
  (@provider.security_protocol == 'non-ssl') ? (proto = 'http') : (proto = 'https')

  connection_hash = {
    :openstack_api_key => @provider.authentication_password,
    :openstack_username => @provider.authentication_userid,
    :openstack_auth_url => "#{proto}://#{@provider.hostname}:#{@provider.port}#{conn_ref}",
    :openstack_tenant => tenant,
  }
  connection_hash[:openstack_endpoint_type] = endpoint if type == 'Identity'
  # if the openstack environment is using keystone v3, add two keys to hash and replace the auth_url
  if @provider.api_version == 'v3'
    connection_hash[:openstack_domain_name] = 'Default'
    connection_hash[:openstack_project_name] = tenant
    connection_hash[:openstack_auth_url] = "#{proto}://#{@provider.hostname}:35357/#{conn_ref}"
  end
  return Object::const_get("Fog").const_get("#{type}").const_get("OpenStack").new(connection_hash)
end

def call_rest(url, method, headers, payload=nil)
  require 'rest-client'
  require 'json'
  log(:info, "Call REST: #{url} with type #{method}, headers #{headers}, payload #{payload rescue "nil"}")
  params = {
    :method => method,
    :url => url,
    :headers => headers
  }
  params[:payload] = JSON.generate(payload) unless payload.nil?
  log(:info, "#{JSON.pretty_generate(payload)}") unless payload.nil?
  response = RestClient::Request.new(params).execute
  return response
end


begin
  dump_root
  @vm  = $evm.root['vm']
  raise "vm not found" if @vm.nil?
  port_id = $evm.root['dialog_neutron_port']
  log(:info, "Found VM: #{@vm.name} vendor: #{@vm.vendor}")
  log(:info, "Detaching neutron port with ID #{port_id}")
  @provider  = @vm.ext_management_system
  conn = get_fog_object("Compute", $evm.vmdb(:cloud_tenant).find_by_id(@vm.cloud_tenant_id).name)
  headers = { :content_type => :json, :accept => :json, "X-Auth-Token" => "#{conn.auth_token}" }
  details = conn.get_server_details(@vm.ems_ref)
  nova_url = details.body['server']['links'].detect { |link| link["rel"] == "self" }
  response = call_rest("#{nova_url["href"]}/os-interface/#{port_id}", :delete, headers, nil)
  log(:info, "DetachResponse: #{response.inspect}")
  @vm.refresh

  # Set Ruby rescue behavior
rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

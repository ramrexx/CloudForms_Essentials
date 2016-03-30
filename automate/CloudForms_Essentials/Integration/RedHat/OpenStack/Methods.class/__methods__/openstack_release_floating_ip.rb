=begin
  openstack_release_floating_ip.rb

  Author: Dave Costakos <david.costakos@redhat.com>, Kevin Morey <kevin@redhat.com>

  Description: This method Releases all floating IPs on a VM
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

def get_fog_object(type='Compute', tenant='admin', endpoint='adminURL')
  require 'fog'
  (@provider.api_version == 'v2') ? (conn_ref = '/v2.0/tokens') : (conn_ref = '/v3/auth/tokens')
  (@provider.security_protocol == 'non-ssl') ? (proto = 'http') : (proto = 'https')

  connection_hash = {
    :provider => 'OpenStack',
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
  return Object::const_get("Fog").const_get("#{type}").new(connection_hash)
end

begin
  $evm.root.attributes.sort.each { |k, v| log(:info, "\t $evm.root Attribute - #{k}: #{v}")}

  case $evm.root['vmdb_object_type']
  when 'miq_provision'
    @task = $evm.root['miq_provision']
    log(:info, "Task: #{@task.id} Request: #{@task.miq_request.id} Type:#{@task.type}")
    @vm = @task.vm
    ws_values = @task.options.fetch(:ws_values, {})
    @vm = @task.vm
    floating_network = ws_values[:floating_network] || @task.get_option(:floating_network)
  when 'vm'
    # get vm from root
    @vm = $evm.root['vm']
    floating_network = $evm.root['dialog_floating_network']
  else
    exit MIQ_OK
  end

  @provider = @vm.ext_management_system
  log(:info, "vm: #{@vm.name} uuid: #{@vm.ems_ref} provider: #{@provider.name} ipaddresses: #{@vm.ipaddresses}")

  tenant = $evm.vmdb(:cloud_tenant).find_by_id(@vm.cloud_tenant_id)
  log(:info, "Connecting to tenant #{tenant.name}")
  conn = get_fog_object("Compute", tenant.name)
  netconn = get_fog_object("Network", tenant.name)

  server_details = conn.get_server_details(@vm.ems_ref).body['server']
  log(:info, "Got OpenStack server details: #{server_details.inspect}")
  addresses = server_details['addresses']

  release_addrs = []
  addresses.each_pair { |network, details|
    for address in details
      if address['OS-EXT-IPS:type'] == "floating"
        log(:info, "Found floating addr #{address.inspect}")
        release_addrs.push("#{address['addr']}")
      end
    end
  }

  for addr in release_addrs
    log(:info, "Reclaiming: #{addr}")
    # must get the floating id from neutron
    floating = netconn.list_floating_ips.body['floatingips']
    for ip in floating
      if ip['floating_ip_address'] == "#{addr}"
        id = ip['id']
        log(:info, "Floating ID for #{addr} is #{id}")
        begin
          netconn.disassociate_floating_ip(id)
          log(:info, "Disassociated #{addr}")
          netconn.delete_floating_ip(id)
          log(:info, "Reclaimed #{addr}")
        rescue => neutronerr
          log(:error, "Error reclaiming #{addr} #{neutronerr}\n#{neutronerr.backtrace.join("\n")}")
        end
      end
    end
  end

  @vm.custom_set("NEUTRON_floating_id", nil)
  @vm.custom_set("NEUTRON_floating_ip", nil)
  @vm.refresh

rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

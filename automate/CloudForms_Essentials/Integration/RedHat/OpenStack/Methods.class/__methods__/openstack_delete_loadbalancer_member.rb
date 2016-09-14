=begin
  openstack_delete_loadbalancer_member.rb

  Author: David Costakos <dcostako@redhat.com>

  Description: This method deletes a member from a load balancer

-------------------------------------------------------------------------------
   Copyright 2016 David Costakos <dcostako@redhat.com>

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

def get_provider(provider_id=nil)
  # if we get pass the provider_id when calling the method...
  if provider_id
    provider = $evm.vmdb(:ManageIQ_Providers_Openstack_CloudManager).find_by_id(provider_id)
  else
    # otherwise, pull the provider_id from the dialog options
    $evm.root.attributes.detect { |k,v| provider_id = v if k.end_with?('provider_id') } rescue nil
    provider = $evm.vmdb(:ManageIQ_Providers_Openstack_CloudManager).find_by_id(provider_id)
  end

  if provider
    log(:info, "Found provider: #{provider.name} via provider_id: #{provider.id}")
  else
    # if all else fails, grab the first provider of this type
    provider = $evm.vmdb(:ManageIQ_Providers_Openstack_CloudManager).first
    log(:info, "Found provider: #{provider.name} via default method")
  end
  provider ? (return provider) : (return nil)
end

def remove_members(pool_id, netconn)
  log(:info, "Removing members from #{pool_id}")
  members = netconn.list_lb_members(:pool_id => pool_id)[:body]["members"]
  log(:info, "Members #{members.inspect}")
  for member in members
    log(:info, "Deleteing Member: #{member["id"]}")
    netconn.delete_lb_member(member["id"])
    log(:info, "Deleted member #{member["id"]}")
  end
  log(:info, "Done Removing members from #{pool_id}")
end

def remove_monitor(monitor_id, pool_id, netconn)
  log(:info, "Disassociating Monitor #{monitor_id} from #{pool_id}")
  netconn.disassociate_lb_health_monitor(pool_id, monitor_id)
  log(:info, "Disassociated #{monitor_id}")

  log(:info, "Deleting Monitor #{monitor_id}")
  begin
    netconn.delete_lb_health_monitor(monitor_id)
    log(:info, "Successfully deleted monitor #{monitor_id}")
  rescue lberr
    log(:error, "Error delete monitor #{monitor_id} #{lberr.class} [#{lberr}]")
    log(:error, "#{lberr.backtrace.join("\n")}")
    log(:error, "Continuing anyway")
  end
end

def remove_vip(vip_id, pool_id, netconn)
  log(:info, "Reclaiming VIP #{vip_id} from pool #{pool_id}")
  netconn.delete_lb_vip(vip_id)
  log(:info, "Deleted VIP #{vip_id}")
end

def remove_pool(pool_id, netconn)
  log(:info, "Cleaning up pool #{pool_id}")
  netconn.delete_lb_pool(pool_id)
  log(:info, "Deleted LB Pool #{pool_id}")
end

def return_floatingip(floatingip_id, netconn)
  log(:info, "Returning floating ip #{floatingip_id} to the available pool")
  netconn.delete_floating_ip(floatingip_id)
  log(:info, "Returned floating ip #{floatingip_id}")
end

begin
  $evm.root.attributes.sort.each { |k, v| log(:info, "\t $evm.root Attribute - #{k}: #{v}")}







  service = $evm.root['service']

  raise "Unable to find service in $evm.root['service']" if service.nil?

  floatingip_id = service.custom_get("FLOATING_IP")
  pool_id = service.custom_get("POOL_ID")
  monitor_id = service.custom_get("MONITOR_ID")
  vip_id = service.custom_get("VIP_ID")

  tenant_tag = service.tags.select {
    |tag_element| tag_element.starts_with?("cloud_tenants/")
  }.first.split("/", 2).last



  log(:info, "floatingip_id: #{floatingip_id rescue nil}")
  log(:info, "pool_id:       #{pool_id rescue nil}")
  log(:info, "monitor_id:    #{monitor_id rescue nil}")
  log(:info, "vip_id:        #{vip_id rescue nil}")
  log(:info, "tenant:        #{tenant_tag rescue nil}")

  # For now, let's just choose the first one.
  openstack = $evm.vmdb(:ems_openstack).all.first
  log(:info, "Logging with with tenant: #{tenant_tag}")
  netconn = Fog::Network.new({
                               :provider => 'OpenStack',
                               :openstack_api_key => openstack.authentication_password,
                               :openstack_username => openstack.authentication_userid,
                               :openstack_auth_url => "http://#{openstack[:hostname]}:#{openstack[:port]}/v2.0/tokens",
                               :openstack_tenant => tenant_tag
  })
  log(:info, "Logged into OpenStack successfully")

  remove_members(pool_id, netconn)
  remove_monitor(monitor_id, pool_id, netconn)
  remove_vip(vip_id, pool_id, netconn)
  remove_pool(pool_id, netconn)
  return_floatingip(floatingip_id, netconn) unless floatingip_id.blank?

  log(:info, "Removing Service from the VMDB")
  service.remove_from_vmdb
  log(:info, "End Automate Method")

rescue => err
  log(:error, "Unexpected Exception: [#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

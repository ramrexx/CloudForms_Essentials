=begin
  openstack_create_loadbalancer_member.rb

  Author: David Costakos <dcostako@redhat.com>

  Description: This method adds a member to a load balancer

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

def dump_root()
  log(:info, "Root:<$evm.root> Begin $evm.root.attributes")
  $evm.root.attributes.sort.each { |k, v| log(:info, "Root:<$evm.root> Attribute - #{k}: #{v}")}
  log(:info, "Root:<$evm.root> End $evm.root.attributes")
  log(:info, "")
end

def list_load_balancers(conn)
  res = conn.list_lb_pools.body['pools']
  log(:info, "List_LB_POOLS: #{res.inspect}")
  return res
end



dump_root

require 'fog/openstack'
require 'netaddr'

vm = $evm.root['vm']
newvm = $evm.vmdb('vm').all.detect { |tvm| tvm.ems_ref == vm.ems_ref }
log(:info, "Got VM object instead of VM or Template I think")
log(:info, "NEWVM: #{newvm.inspect}")
log(:info, "OLDVM: #{vm.inspect}")
vm = newvm
# For now, let's just choose the first one.
openstack = vm.ext_management_system

netconn = Fog::Network.new({
                             :provider => 'OpenStack',
                             :openstack_api_key => openstack.authentication_password,
                             :openstack_username => openstack.authentication_userid,
                             :openstack_auth_url => "http://#{openstack[:hostname]}:#{openstack[:port]}/v2.0/tokens",
                             :openstack_tenant => "admin"
})

conn = Fog::Compute.new({
                          :provider => 'OpenStack',
                          :openstack_api_key => openstack.authentication_password,
                          :openstack_username => openstack.authentication_userid,
                          :openstack_auth_url => "http://#{openstack[:hostname]}:#{openstack[:port]}/v2.0/tokens",
                          :openstack_tenant => "admin"
})


log(:info, "Got Dialog Values")

pool_id = $evm.root['dialog_pool_id']
host_port = $evm.root['dialog_protocol_port']

load_balancers = list_load_balancers(netconn)
mylb = nil
for lb in load_balancers
  mylb = lb if lb['id'] == "#{pool_id}"
end
raise "Unable to find load balancer #{pool_id}" if mylb.nil?

server_details = conn.get_server_details(vm.ems_ref).body['server']
log(:info, "Got OpenStack server details: #{server_details.inspect}")
addresses = server_details['addresses']
fixed_addr = nil
addresses.each_pair { |network, details|
  for address in details
    if address['OS-EXT-IPS:type'] != "floating"
      log(:info, "Found fixed addr #{address.inspect}")
      fixed_addr = "#{address['addr']}"
    end
  end
}

member = netconn.create_lb_member(pool_id, "#{fixed_addr}", host_port, 1)
member = member.body
log(:info, "Created LB Member: #{member.inspect}")

services = $evm.vmdb('service').all

#prov = vm.miq_provision
for service in services
  log(:info, "Inspect service #{service.inspect}: #{service.name}")
  if service.name.start_with?("LBaaS #{mylb['name']}:")
    log(:info, "Found Service; #{service.name}")
    vm.add_to_service(service)
    vm.refresh
  else
    log(:info, "No match on #{service.name} #{mylb['name']}")
  end
end

rescue => err
  log(:error, "Unexpected Exception: [#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

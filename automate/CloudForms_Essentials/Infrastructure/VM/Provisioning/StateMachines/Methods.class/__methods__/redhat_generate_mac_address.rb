=begin
 redhat_generate_mac_address.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method generates a mac address for RHEV VMs
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

def generate_unique_macaddress(nic_prefix)
  # Check up to 50 times for the existence of a randomly generated mac address
  for i in (1..50)
    new_macaddress = "#{nic_prefix}"+"#{("%02X" % rand(0x3F)).downcase}:"
    new_macaddress += "#{("%02X" % rand(0xFF)).downcase}:#{("%02X" % rand(0xFF)).downcase}"
    log(:info, "Attempt #{i} - Checking for existence of mac_address: #{new_macaddress}")
    return new_macaddress if $evm.vmdb(:vm).all.detect \
      {|v| v.mac_addresses.include?(new_macaddress)}.nil?
  end
end

begin

  nic_prefix = '00:1a:4a:'

  case $evm.root['vmdb_object_type']
  when 'miq_provision'
    # Get provisioning object
    @task = $evm.root["miq_provision"]
    log(:info, "Provision: #{@task.id} Request: #{@task.miq_provision_request.id} " \
                           "provision_type: #{@task.get_option(:provision_type)}")

  when 'vm'
    # for testing purposes only
    vm = $evm.root['vm']
    log(:info, "VM: #{vm.name} mac_addresses: #{vm.mac_addresses}")
    macaddress = generate_unique_macaddress(nic_prefix)
    raise if macaddress.nil?
    log(:info, "Found available macaddress: #{macaddress}")
    exit MIQ_OK
  end

  # Build case statement to determine which type of processing is required
  case @task.get_option(:provision_type)
  when 'native_clone'
    macaddress = generate_unique_macaddress(nic_prefix)
    #@task.set_network_adapter(0, {:mac_address => macaddress})
    @task.set_option(:mac_address, macaddress)
    log(:info, "Provisioning option updated {:mac_address=>" \
                           "#{@task.get_option(:mac_address)}}", true)
  when 'pxe'
    macaddress = generate_unique_macaddress(nic_prefix)
    #@task.set_network_adapter(0, {:mac_address => macaddress})
    @task.set_option(:mac_address, macaddress)
    log(:info, "Provisioning option updated {:mac_address=>" \
                           "#{@task.get_option(:mac_address)}}", true)
  when 'iso'
    macaddress = generate_unique_macaddress(nic_prefix)
    #@task.set_network_adapter(0, {:mac_address => macaddress})
    @task.set_option(:mac_address, macaddress)
    log(:info, "Provisioning option updated {:mac_address=>" \
                           "#{@task.get_option(:mac_address)}}", true)
  else
    log(:info, "provision_type: #{@task.get_option(:provision_type)} does " \
                           "not match, skipping method...")
  end

rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_STOP
end

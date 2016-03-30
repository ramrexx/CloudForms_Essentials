=begin
  vcenter_vmotion_vm.rb

  Author: Kevin Morey <kevin@redhat.com>

  Description: This method vMotions a VM in vCenter

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

def login(client, username, password)
  result = client.call(:login) do
    message( :_this => "SessionManager", :userName => username, :password => password )
  end
  client.globals.headers( { "Cookie" => result.http.headers["Set-Cookie"] } )
end

def logout(client)
  begin
    client.call(:logout) do
      message(:_this => "SessionManager")
    end
  rescue => logouterr
    log(:error, "Error logging out #{logouterr.class} #{logouterr}")
  end
end

begin
  require 'savon'

  $evm.root.attributes.sort.each { |k, v| log(:info,"Root:<$evm.root> Attributes - #{k}: #{v}")}

  # Get vm object from root
  vm = $evm.root['vm']
  raise "VM object not found" if vm.nil?

  # This method only works with VMware VMs currently
  raise "Invalid vendor:<#{vm.vendor}>" unless vm.vendor.downcase == 'vmware'

  log(:info,"Detected VM: #{vm.name} vendor: #{vm.vendor} provider: #{vm.ext_management_system.name} ems_ref: #{vm.ems_ref}")

  # get resource_pool.ems_ref from root
  resource_pool_ems_ref = $evm.root['dialog_resource_pool_ems_ref']
  datastore_ems_ref = $evm.root['dialog_datastore_ems_ref']

  # get servername and credentials from vm.ext_management_system
  servername = vm.ext_management_system.ipaddress
  username = vm.ext_management_system.authentication_userid
  password = vm.ext_management_system.authentication_password

  client = Savon.client(
    :wsdl => "https://#{servername}/sdk/vim.wsdl",
    :endpoint => "https://#{servername}/sdk/",
    :ssl_verify_mode => :none,
    :ssl_version => :TLSv1,
    :raise_errors => false,
    :log_level => :info,
    :log => false
  )
  #client.operations.sort.each { |operation| log(:info, "Savon Operation: #{operation}") }

  # login and set cookie
  login(client, username, password)

  body_hash={}
  body_hash['_this'] = vm.ems_ref
  body_hash[:attributes!] = { 'type' => 'VirtualMachine' }
  body_hash['spec'] = {}
  body_hash['spec']['datastore'] = datastore_ems_ref unless datastore_ems_ref.nil? && vm.storage.ems_ref == datastore_ems_ref
  body_hash['spec']['pool'] = resource_pool_ems_ref unless resource_pool_ems_ref.nil? && vm.resource_pool.ems_ref == resource_pool_ems_ref
  body_hash['spec'][:attributes!]   = {'type' =>  'VirtualMachineRelocateSpec'}

  log(:info, "vMotioning vm: #{vm.name} using bodyhash: #{body_hash}")
  result = client.call(:relocate_vm_task, :message => body_hash)
  log(:warn, "result body: #{result.body[:relocate_vm_task_response].inspect}")
  log(:info, "result success?: #{result.success?}")

  logout(client)

rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

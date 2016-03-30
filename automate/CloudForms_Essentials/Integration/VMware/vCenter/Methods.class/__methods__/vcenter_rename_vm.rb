=begin
  vcenter_rename_vm.rb

  Author: Kevin Morey <kevin@redhat.com>

  Description: This method renames a VM in vCenter

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
  client.globals.headers({ "Cookie" => result.http.headers["Set-Cookie"] })
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

def call_vCenter(soap_action, body_hash, vm)
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

  begin
    result = client.call(soap_action) do
      message( body_hash ).to_hash
    end
  rescue => soap_error
    log(:error, "Error calling soap_action: #{soap_action} error: #{soap_error.class} #{soap_error} result: #{result.inspect rescue nil}")
  end
  log(:info, "result.success?: #{result.success?}")

  # logout
  logout(client)

  log(:info, "response: #{result.body["#{soap_action}_response".to_sym]}")
  return result.body["#{soap_action}_response".to_sym]
end

begin

  require 'savon'

  # Get vm object from root
  vm = $evm.root['vm']
  raise "VM object not found" if vm.nil?

  # This method only works with VMware VMs currently
  raise "Invalid vendor:<#{vm.vendor}>" unless vm.vendor.downcase == 'vmware'

  # Get dialog_size variable from root hash if nil convert to zero
  vm_name = $evm.root['dialog_new_vm_name']

  log(:info,"Detected VM: #{vm.name} vendor: #{vm.vendor} provider: #{vm.ext_management_system.name} ems_ref: #{vm.ems_ref} new_name: #{vm_name}")
  raise "missing $evm.root['dialog_vm_name']" if vm_name.nil?

  body_hash = { '_this' => vm.ems_ref, :attributes! => { 'type' => "VirtualMachine"}, "newName" => ["#{vm_name}"] }

  # perform Rename_Task
  response = call_vCenter(:rename_task, body_hash, vm)
  log(:info, "response: #{response.inspect}")

rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

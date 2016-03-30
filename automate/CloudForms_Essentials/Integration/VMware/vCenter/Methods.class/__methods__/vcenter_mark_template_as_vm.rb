=begin
  vcenter_mark_template_as_vm.rb

  Author: Kevin Morey <kevin@redhat.com>

  Description: This method marks a VMware template as a VM
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
def log(level, msg, update_message=false)
  $evm.log(level, "#{msg}")
end

def dump_root()
  log(:info, "Begin $evm.root.attributes")
  $evm.root.attributes.sort.each { |k, v| log(:info, "\t Attribute: #{k} = #{v}")}
  log(:info, "End $evm.root.attributes")
  log(:info, "")
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

  dump_root()

  # Get vm object from root
  vm = $evm.root['vm']
  raise "VM object not found" if vm.nil?

  # This method only works with VMware VMs currently
  raise "Invalid vendor: #{vm.vendor}" unless vm.vendor.downcase == 'vmware'

  log(:info, "Detected VM: #{vm.name} vendor: #{vm.vendor} provider: #{vm.ext_management_system.name} ems_ref: #{vm.ems_ref}")

  # get resource_pool.ems_ref from root
  resource_pool = $evm.root['dialog_resource_pool']

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

  mark_as_virtual_machine_result = client.call(:mark_as_virtual_machine) do
    message( { '_this' => vm.ems_ref, :attributes! => { 'type' => "VirtualMachine"},
               'pool' => resource_pool } ).to_hash
  end
  log(:info, "mark_as_virtual_machine_result success?: #{mark_as_virtual_machine_result.success?}")

  logout(client)


  # Set Ruby rescue behavior
rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

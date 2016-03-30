=begin
  vcenter_resize_disk.rb

  Author: Kevin Morey <kevin@redhat.com>

  Description: This method is used to increase the size of a VMWare VMs disk

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

# Error logging convenience
def log_err(err)
  log(:error, "#{err.class} #{err}")
  log(:error, "#{err.backtrace.join("\n")}")
end

def get_vcenter_savon_obj(servername, username, password)
  client = Savon.client(
    :wsdl => "https://#{servername}/sdk/vim.wsdl",
    :endpoint => "https://#{servername}/sdk/",
    :ssl_verify_mode => :none,
    :ssl_version => :TLSv1,
    :log_level => :info,
    :log => false,
    :raise_errors => false
  )

  begin
    result = client.call(:login) do
      message(
        :_this => "SessionManager",
        :userName => username,
        :password => password
      )
    end
    client.globals.headers({"Cookie" => result.http.headers["Set-Cookie"]})
    return client
  rescue => loginerr
    log_err(loginerr)
    return nil
  end
end

def vcenter_logout(client)
  require 'savon'
  begin
    client.call(:logout) do
      message(:_this => "SessionManager")
    end
  rescue => logouterr
    log_err(logouterr)
  end
end

def resizeDisk(vm, disk_number, new_disk_size_in_kb)
  vcenter_mgt = vm.ext_management_system
  client = nil
  begin
    client = get_vcenter_savon_obj(vcenter_mgt.hostname,
                                   vcenter_mgt.authentication_userid,
                                   vcenter_mgt.authentication_password)

    message_hash = {
      :_this => "propertyCollector",
      :specSet => {
        :propSet => {
          :type => "VirtualMachine",
          :pathSet => "config.hardware"
        },
        :objectSet => {
          :obj => vm.ems_ref,
          :skip => false,
          :attributes! => { :obj => { 'type' => "VirtualMachine" } }
        }
      },
      :attributes! => { :_this => { 'type' => "PropertyCollector" } }
    }
    log(:info, "Calling Get Hardware Config with #{message_hash.inspect}")
    vm_config_result = client.call(:retrieve_properties, message: message_hash).to_hash[:retrieve_properties_response][:returnval]

    log(:info, "Hardware Props Response: #{vm_config_result.inspect}")

    mydisk = nil
    currentIndex = 0
    vm_config_result[:prop_set][:val][:device].each { |device|
      log(:debug, "DEVICE -> ")
      log(:debug, "TYPE -> #{device[:"@xsi:type"]}")
      device.each {|k,v| log(:debug, " ++ #{k} => #{v}") }
      if "#{device[:"@xsi:type"]}" == "VirtualDisk"
        log(:info, "Device is a disk #{currentIndex}")
        if currentIndex == disk_number
          mydisk = device
          break
        else
          currentIndex += 1
        end
      end
    }

    raise "Could not find disk at index disk_number" if mydisk.nil?

    message_hash = {
      :_this => vm.ems_ref,
      :spec => {
        :deviceChange => [{
                            :operation => "edit".freeze,
                            :device => {
                              :key => mydisk[:key],
                              :controller_key => mydisk[:controller_key],
                              :unit_number => mydisk[:unit_number],
                              :capacity_in_kB => new_disk_size_in_kb
                            },
                            :attributes! => {
                              #:operation => { "xsi:type" => "vim25:VirtualDeviceConfigSpec" },
                              :device => { "xsi:type" => "vim25:VirtualDisk" }
                            }
        }],
        #:attributes! => { :deviceChange => { "xsi:type" => "vim25:ArrayOfVirtualDeviceConfigSpec" } }
      },
      :attributes! => {
        :_this => { 'xsi:type' => "vim25:VirtualMachine" },
        :spec  => { 'xsi:type' => "vim25:VirtualMachineConfigSpec" }
      }
    }
    log(:info, "Calling reconfigure task with message #{message_hash.inspect}")
    response = client.call(:reconfig_vm_task, message: message_hash).to_hash
    log(:info, "Grow Response: #{response.inspect}")

  ensure
    vcenter_logout(client) unless client.nil?
  end
end

begin
  require 'savon'

  # Get vm object from root
  vm = $evm.root['vm']
  raise "VM object not found" if vm.nil?

  # This method only works with VMware VMs currently
  raise "Invalid vendor: #{vm.vendor}" unless vm.vendor.downcase == 'vmware'

  # Get dialog_disk_number variable from root hash if nil convert to zero
  disk_number = $evm.root['dialog_disk_number'].to_i
  raise "Invalid Disk Number: #{disk_number}" if disk_number.zero?

  # Get dialog_size variable from root hash if nil convert to zero
  size = $evm.root['dialog_size'].to_i

  log(:info,"Detected VM: #{vm.name} vendor: #{vm.vendor} disk_number: #{disk_number.inspect} size: #{size.inspect}")

  new_disk_size_in_kb = size * (1024**2)
  log(:info, "New size in KB: #{new_disk_size_in_kb}")

  unless size.zero?
    log(:info,"VM:<#{vm.name}> Increasing Disk #{disk_number} size to #{new_disk_size_in_kb / 1024**2}GB")
    # Subtract 1 from the disk_number since VMware starts at 0 and CFME start at 1
    disk_number -= 1
    resizeDisk(vm, disk_number, new_disk_size_in_kb)
  end

rescue => err
  log_err(err)
  exit MIQ_ABORT
end

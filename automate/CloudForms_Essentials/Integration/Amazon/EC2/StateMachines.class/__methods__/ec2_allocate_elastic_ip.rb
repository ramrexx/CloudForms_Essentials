=begin
 ec2_allocate_elastic_ip.rb

 Author: David Costakos <dcostako@redhat.com>, Kevin Morey <kevin@redhat.com>

 Description: This method allocates an AWS elastic IP
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

def get_aws_client(type='EC2', constructor='Client')
  require 'aws-sdk'
  
  username = @provider.authentication_userid
  password = @provider.authentication_password
  Aws.config[:credentials] = Aws::Credentials.new(username, password)
  Aws.config[:region]      = @provider.provider_region
  return Aws::const_get("#{type}")::const_get("#{constructor}").new()
end

begin
  $evm.root.attributes.sort.each { |k, v| log(:info, "\t$evm.root Attribute - #{k}: #{v}")}

  case $evm.root['vmdb_object_type']
  when 'vm'
    vm = $evm.root['vm']
    log(:info,"VM: #{vm.name}")
    @provider = vm.ext_management_system
  else
    exit MIQ_OK
  end

  ec2 = get_aws_client()

  allocate_address_hash = ec2.allocate_address.to_h
  # {:public_ip=>"52.39.221.34", :domain=>"vpc", :allocation_id=>"eipalloc-0260e665"}
  log(:info, "allocate_address_hash: #{allocate_address_hash.inspect}")

  elastic_ip = allocate_address_hash[:public_ip]
  allocation_id = allocate_address_hash[:allocation_id]
  vm.custom_set("ELASTIC_IP", elastic_ip.to_s)
  vm.custom_set("ALLOCATION_ID", allocation_id.to_s)
  vm.refresh

  # Note that if you want to release this allocation you can do something like this
  # ec2.release_address({'allocation_id'=>allocate_address_hash[:allocation_id]})

rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

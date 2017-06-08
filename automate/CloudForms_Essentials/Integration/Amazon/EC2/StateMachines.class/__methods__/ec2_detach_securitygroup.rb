=begin
 ec2_detach_securitygroup.rb

 Author: Kevin Morey <kevin@redhat.com>, Nate Stephany <nate@redhat.com>

 Description: This method is used to detach a security group to an Amazon instance
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
  @vm = $evm.root['vm']
  @provider = @vm.ext_management_system

  sg_input = $evm.root['dialog_securitygroup_id'] || $evm.root['dialog_securitygroup_emsref'] ||
    $evm.object['securitygroup_emsref']

  # populate this or pull from instance with $evm.object
  security_group = @provider.security_groups.detect {|sg| sg.ems_ref == sg_input } ||
    @provider.security_groups.detect {|sg| sg.id == sg_input }
  log(:info, "Working with EC2 instance #{@vm.name} to assign security group #{security_group.description}")

  ec2 = get_aws_client

  existing_sg = ec2.describe_instance_attribute({instance_id: @vm.uid_ems, attribute: 'groupSet'}).to_h[:groups]
  log(:info, "EC2 instance #{@vm.ems_ref} currently has security groups #{existing_sg} assigned")

  new_securitygroup_array = []
  existing_sg.each do |sg| 
    next if sg[:group_id] == security_group.ems_ref
    new_securitygroup_array << sg[:group_id] 
  end
  log(:info, "new_securitygroup_array: #{new_securitygroup_array.uniq}")

  ec2.modify_instance_attribute({instance_id: @vm.uid_ems, groups: new_securitygroup_array.uniq})
  new_sg = ec2.describe_instance_attribute({instance_id: @vm.uid_ems, attribute: 'groupSet'}).to_h
  log(:info, "EC2 instance #{new_sg[:instance_id]} has security groups #{new_sg[:groups]} assigned")
  @vm.custom_set(:ec2_securitygroup_policy, 'FAIL')
  @vm.refresh

rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

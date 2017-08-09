=begin
 ec2_tag_vm_owners.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method is used to automatically tag ec2 vms with an AWS owner
-------------------------------------------------------------------------------
   Copyright 2017 Kevin Morey <kevin@redhat.com>

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

def process_tags(category, single_value, tag)
  # Convert to lower case and replace all non-word characters with underscores
  category_name = category.to_s.downcase.gsub(/\W/,'_')
  tag_name = tag.to_s.downcase.gsub(/\W/,'_')

  # if the category exists else create it
  unless $evm.execute('category_exists?', category_name)
    log(:info, "Category <#{category_name}> doesn't exist, creating category")
    $evm.execute('category_create', :name => category_name, :single_value => single_value, :description => "#{category}")
  end
  # if the tag exists else create it
  unless $evm.execute('tag_exists?', category_name, tag_name)
    log(:info, "Adding new tag <#{tag_name}> in Category <#{category_name}>")
    $evm.execute('tag_create', category_name, :name => tag_name, :description => "#{tag}")
  end
  return category_name, tag_name
end

def get_aws_owner_id(vm, category)
  ec2 = get_aws_client
  reservations = ec2.describe_instances.reservations
  ec2_instance = reservations.detect {|r| r.instances.each {|i| 'instance_id' == vm.ems_ref}}
  log(:info, "EC2 instance: #{ec2_instance}")
  log(:info, "EC2 owner_id: #{ec2_instance.owner_id}")
  tag = ec2_instance.owner_id
  category_name, tag_name = process_tags(category, true, tag)
  vm.tag_assign("#{category_name}/#{tag_name}")
end

begin
  category = 'AWS Owner id'

  case $evm.root['vmdb_object_type']
  when 'ext_management_system'
    @provider = $evm.root['ext_management_system']
    @provider.vms.each do |vm|
      get_aws_owner_id(vm, category)
    end
  when 'vm'
    vm = $evm.root['vm']
    @provider = vm.ext_management_system
    get_aws_owner_id(vm, category)
  end

rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

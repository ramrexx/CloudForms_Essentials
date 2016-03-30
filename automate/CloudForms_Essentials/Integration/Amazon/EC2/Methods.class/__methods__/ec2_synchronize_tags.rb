=begin
 ec2_synchronize_tags.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method synchronizes tags between a VM and its corresponding EC2 instance
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

def retry_method(retry_time, msg)
  log(:info, "#{msg} - Waiting #{retry_time} seconds}", true)
  $evm.root['ae_result'] = 'retry'
  $evm.root['ae_retry_interval'] = retry_time
  exit MIQ_OK
end

def get_aws_client(type='EC2')
  require 'aws-sdk'
  AWS.config(
    :access_key_id => @provider.authentication_userid,
    :secret_access_key => @provider.authentication_password,
    :region => @provider.provider_region
  )
  return Object::const_get("AWS").const_get("#{type}").new()
end

def process_tags( category, category_description, single_value, tag, tag_description)
  # Convert to lower case and replace all non-word characters with underscores
  category_name = category.to_s.downcase.gsub(/\W/, '_')
  tag_name = tag.to_s.downcase.gsub(/\W/, '_')
  unless $evm.execute('category_exists?', category_name)
    log(:info, "Creating Category {#{category_name} => #{category_description}}")
    $evm.execute('category_create', :name => category_name, :single_value => single_value, :description => "#{category_description}")
  end
  unless $evm.execute('tag_exists?', category_name, tag_name)
    log(:info, "Creating Tag {#{tag_name} => #{tag_description}} in Category #{category_name}")
    $evm.execute('tag_create', category_name, :name => tag_name, :description => "#{tag_description}")
  end
  return category_name, tag_name
end

begin
  case $evm.root['vmdb_object_type']
  when 'miq_provision'
    @task = $evm.root["miq_provision"]
    log(:info, "Provision: #{@task.id} Request: #{@task.miq_provision_request.id} Type: #{@task.type}")
    @vm = @task.vm
    retry_method(15.seconds, "Provisioned instance: #{prov.get_option(:vm_target_name)} not ready") if @vm.nil?
  when 'vm'
    @vm = $evm.root['vm']
  end
  exit MIQ_OK unless (@vm.vendor.downcase rescue nil) == 'amazon'

  @provider = @vm.ext_management_system
  ec2 = get_aws_client('EC2')

  ec2_instance = ec2.instances[@vm.ems_ref]
  log(:info, "VM: #{@vm.name} EC2: #{ec2_instance.id}")

  ec2_instance.tags.each do |key, value|
    #next if key.starts_with?("cfme_")
    next if key.downcase == "name"
    category_name, tag_name = process_tags(key, "EC2 Tag #{key}", true, value, value)
    unless @vm.tagged_with?(category_name,tag_name)
      log(:info, "Assigning Tag: {#{category_name} => #{tag_name}} to VM: #{@vm.name}")
      @vm.tag_assign("#{category_name}/#{tag_name}")
    end
  end

  @vm.tags.each do |tag_element|
    #next if tag_element.starts_with?("folder_path")
    tag = tag_element.split("/", 2)
    log(:info, "Assigning Tag: {#{tag.first} => #{tag.last}} to EC2 Instance: #{@vm.ems_ref}", true)
    ec2_instance.add_tag("#{tag.first}", :value => tag.last.to_s)
  end

rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_STOP
end

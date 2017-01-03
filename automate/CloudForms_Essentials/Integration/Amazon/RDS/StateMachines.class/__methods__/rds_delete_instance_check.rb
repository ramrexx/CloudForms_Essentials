=begin
 rds_delete_instance_check.rb

 Author: David Costakos <dcostako@redhat.com>, Kevin Morey <kevin@redhat.com>

 Description: This method checks that the AWS RDS instance has been deleted
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

def get_provider(provider_id=nil)
  $evm.root.attributes.detect { |k,v| provider_id = v if k.end_with?('provider_id') } rescue nil
  provider = $evm.vmdb(:ManageIQ_Providers_Amazon_CloudManager).find_by_id(provider_id)
  log(:info, "Found provider: #{provider.name} via provider_id: #{provider.id}") if provider

  # set to true to default to the fist amazon provider
  use_default = true
  unless provider
    # default the provider to first openstack provider
    provider = $evm.vmdb(:ManageIQ_Providers_Amazon_CloudManager).first if use_default
    log(:info, "Found amazon: #{provider.name} via default method") if provider && use_default
  end
  provider ? (return provider) : (return nil)
end

def retry_method(retry_time='1.minute', msg='RETRYING', update_message=false)
  log(:info, "#{msg} - retrying in #{retry_time}}", update_message)
  $evm.root['ae_result'] = 'retry'
  $evm.root['ae_retry_interval'] = retry_time
  exit MIQ_OK
end

def get_aws_client(type='RDS', constructor='Client', body_hash={})
  require 'aws-sdk'

  username = @provider.authentication_userid
  password = @provider.authentication_password
  Aws.config[:credentials] = Aws::Credentials.new(username, password)
  Aws.config[:region]      = @provider.provider_region
  return Aws::const_get("#{type}")::const_get("#{constructor}").new(body_hash)
end

def set_service_custom_variables(hash)
  hash.each do |k,v|
    next if v.kind_of?(Array) || v.kind_of?(Hash)
    @service.custom_set(k, v.to_s)
  end
  @service.custom_set('Last Refresh', Time.now.utc.strftime('%Y-%m-%d %H:%M:%S UTC'))
end

begin
  $evm.root.attributes.sort.each { |k, v| log(:info, "\t$evm.root Attribute - #{k}: #{v}")}

  case $evm.root['vmdb_object_type']
  when 'service'
    @service = $evm.root['service']
    log(:info,"Service: #{@service.name} Id: #{@service.id}")
    provider_id   = @service.custom_get(:provider_id)
    @provider ||= get_provider(provider_id)
  else
    exit MIQ_OK
  end

  db_instance_identifier = @service.custom_get(:db_instance_identifier)

  rds = get_aws_client
  log(:info, "RDS Client: #{rds}")
  begin
    rds_delete_instnace_check_hash = rds.describe_db_instances({:db_instance_identifier => db_instance_identifier})[:db_instances].first.to_h
    set_service_custom_variables(rds_delete_instnace_check_hash)
    status_message = "DB Instance: #{db_instance_identifier} status: #{rds_delete_instnace_check_hash[:db_instance_status]}"
    log(:info, status_message, true)
    retry_method('1.minute', status_message)
  rescue AWS::RDS::Errors::DBInstanceNotFound => dberr
    log(:info, "Database instance: #{db_instance_identifier} has been deleted, #{dberr}", true)
    @service.remove_from_vmdb if @service
    exit MIQ_OK
  end

rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

=begin
 list_rds_types.rb

 Author: David Costakos <dcostako@redhat.com>, Kevin Morey <kevin@redhat.com>

 Description: This method lists all Amazon RDS types
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

def get_rds_from_management_system(ext_management_system)
  AWS.config(
    :access_key_id => ext_management_system.authentication_userid,
    :secret_access_key => ext_management_system.authentication_password,
    :region => ext_management_system.name
  )
  return AWS::RDS.new()
end

begin

  $evm.root.attributes.sort.each { |k, v| log(:info, "Root:<$evm.root> Attribute - #{k}: #{v}")}

  require 'aws-sdk'

  if $evm.root['dialog_mid']
    aws_mgt = $evm.vmdb(:ManageIQ_Providers_Amazon_CloudManager).find_by_id($evm.root['dialog_mid'])
    log(:info, "Got AWS Mgt System from $evm.root['dialog_mid]")
  elsif $evm.root['vm']
    vm = $evm.root['vm']
    aws_mgt = vm.ext_management_system
    log(:info, "Got AWS Mgt System from VM #{vm.name}")
  else
    aws_mgt = $evm.vmdb(:ems_amazon).first
    log(:info, "Got AWS Mgt System from VMDB")
  end

  dbtype_hash = {}

  client = get_rds_from_management_system(aws_mgt).client
  log(:info, "Got RDS Client: #{client}")
  client.describe_db_engine_versions[:db_engine_versions].each { |engine_version|
    dbtype_hash[engine_version[:engine]] = engine_version[:engine]
  }
  dbtype_hash[''] = nil
  $evm.object['values'] = dbtype_hash
  $evm.object['default_value'] = dbtype_hash.first[0]
  log(:info, "Dynamic drop down values: #{$evm.object['values']}")

rescue => err
  (dbtype_hash||={})["#{err.class}: #{err}"] = "#{err.class}: #{err}"
  $evm.object['values'] = dbtype_hash
  log(:error, "ERROR: Dynamic drop down values: #{$evm.object['values']}")
end

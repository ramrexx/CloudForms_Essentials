=begin
 ec2_create_securitygroup.rb

 Author: David Costakos <dcostako@redhat.com>, Kevin Morey <kevin@redhat.com>

 Description: This method creates a AWS security_group
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
  unless provider_id.nil?
    $evm.root.attributes.detect { |k,v| provider_id = v if k.end_with?('provider_id') } rescue nil
  end
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

def get_aws_client(type='EC2')
  require 'aws-sdk'
  AWS.config(
    :access_key_id => @provider.authentication_userid,
    :secret_access_key => @provider.authentication_password,
    :region => @provider.provider_region
  )
  return Object::const_get("AWS").const_get("#{type}").new().client
end

begin
  $evm.root.attributes.sort.each { |k, v| log(:info, "\t$evm.root Attribute - #{k}: #{v}")}

  case $evm.root['vmdb_object_type']
  when 'service_template_provision_task'
    @task = $evm.root['service_template_provision_task']
    log(:info, "Task: #{@task.id} Request: #{@task.miq_request.id} Type:#{@task.type}")
    @service = @task.destination
    log(:info,"Service: #{@service.name} Id: #{@service.id}")
    @provider = get_provider
  when 'service'
    @service = $evm.root['service']
    log(:info,"Service: #{@service.name} Id: #{@service.id}")
    provider_id   = @service.custom_get(:provider_id)
    @provider ||= get_provider(provider_id)
  else
    exit MIQ_OK
  end

  ec2 = get_aws_client
  log(:info, "Got EC2 Object: #{ec2.inspect}")

  vpc = ec2.vpcs.first
  log(:info, "Deploying to VPC #{vpc.id} #{vpc.cidr_block}")

  tcp_ports = $evm.object['tcp_ports']
  tcp_source_cidr = $evm.object['tcp_source_cidr']
  tcp_source_cidr ||= "0.0.0.0/0"

  security_group = nil
  if tcp_ports
    log(:info, "Enabling TCP Ports: #{tcp_ports} from cidr #{tcp_source_cidr}")
    security_group ||= ec2.security_groups.create("#{@task.get_option(:class_name)}-#{rand(36**3).to_s(36)}",
                                                  { :vpc => vpc.id, :description => "Sec Group for #{@task.get_option(:class_name)}" })
    port_array = tcp_ports.split(',')
    port_array.each { |port|
      security_group.authorize_ingress(:tcp, port.to_i, tcp_source_cidr)
      log(:info, "Enabled ingress on tcp port #{port.to_i} from #{tcp_source_cidr}")
    }
  end

  udp_ports = $evm.object['udp_ports']
  udp_source_cidr = $evm.object['udp_source_cidr']
  udp_source_cidr ||= "0.0.0.0/0"

  if udp_ports
    log(:info, "Enabling UDP Ports #{udp_ports} from cidr #{udp_source_cidr}")
    security_group ||= ec2.security_groups.create("#{@task.get_option(:class_name)}-#{rand(36**3).to_s(36)}")
    port_array = udp_ports.split(',')
    port_array.each { |port|
      security_group.authorize_ingress(:udp, port.to_i, udp_source_cidr)
      log(:info, "Enabled ingress on udp port #{port.to_i} from #{udp_source_cidr}")
    }
  end

  @service.custom_set("SECURITY_GROUP", "#{security_group.id}")

  rds = get_aws_client
  log(:info, "RDS Client: #{rds}")

  rds_delete_status_hash = rds.delete_db_instance({:db_instance_identifier => db_instance_identifier, :skip_final_snapshot => true})

  log(:info, "RDS instance:#{db_instance_identifier} Delete issued: #{rds_delete_status_hash.inspect}")
  set_service_custom_variables(rds_delete_status_hash)

rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

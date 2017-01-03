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

  vpc = ec2.describe_vpcs.first.vpcs.first.to_h
  # {:vpc_id=>"vpc-38a98d5c", :state=>"available", :cidr_block=>"172.16.0.0/16", :dhcp_options_id=>"dopt-a2bdaac0",
  #   :tags=>[{:key=>"AWSServiceAccount", :value=>"180699916525"}], :instance_tenancy=>"default", :is_default=>false}
  vpc_id = vpc[:vpc_id]
  vpc_cidr_block = vpc[:cidr_block]
  log(:info, "Deploying to VPC #{vpc_id} #{vpc_cidr_block}")

  tcp_ports = $evm.object['tcp_ports']
  tcp_source_cidr = $evm.object['tcp_source_cidr']
  tcp_source_cidr ||= "0.0.0.0/0"

  security_group = nil
  if tcp_ports
    log(:info, "Enabling TCP Ports: #{tcp_ports} from cidr #{tcp_source_cidr}")
    security_group ||= ec2.create_security_group(
      {
        :group_name  => "#{@task.get_option(:class_name)}-#{rand(36**3).to_s(36)}",
        :description => "Sec Group for #{@task.get_option(:class_name)}",
        :vpc_id      => vpc_id
      }
    ).to_h
    log(:info, "security_group id: #{security_group[:group_id]}")

    port_array = tcp_ports.split(',')
    port_array.each { |port|
      ec2.authorize_security_group_ingress(
        {
          :group_id    => security_group[:group_id],
          :from_port   => port, # use -1 for all ports
          :cidr_ip     => tcp_source_cidr, # '0.0.0.0/0' for all cidr
          :ip_protocol => 'tcp' # use '-1' for protocols
        }
      )
      log(:info, "Enabled ingress on tcp port #{port.to_i} from #{tcp_source_cidr}")
    }
  end

  udp_ports = $evm.object['udp_ports']
  udp_source_cidr = $evm.object['udp_source_cidr']
  udp_source_cidr ||= "0.0.0.0/0"

  if udp_ports
    log(:info, "Enabling UDP Ports #{udp_ports} from cidr #{udp_source_cidr}")
    security_group ||= ec2.create_security_group(
      {
        :group_name  => "#{@task.get_option(:class_name)}-#{rand(36**3).to_s(36)}",
        :description => "Sec Group for #{@task.get_option(:class_name)}",
        :vpc_id      => vpc_id
      }
    ).to_h

    port_array = udp_ports.split(',')
    port_array.each { |port|
      ec2.authorize_security_group_ingress(
        {
          :group_id    => security_group[:group_id],
          :from_port   => port, # use -1 for all ports
          :cidr_ip     => udp_source_cidr, # '0.0.0.0/0' for all cidr
          :ip_protocol => 'udp' # use '-1' for protocols
        }
      )
      log(:info, "Enabled ingress on udp port #{port.to_i} from #{udp_source_cidr}")
    }
  end

  @service.custom_set("SECURITY_GROUP", "#{security_group.id}")

rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

=begin
  openstack_preprovision.rb

  Author: Kevin Morey <kevin@redhat.com>

  Description: This method is used to apply PreProvision customizations for
               Openstack provisioning

  Mandatory dialog fields: none
  Optional dialog fields: none
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

def add_affinity_group(ws_values)
  # add affinity group id to clone options
  log(:info, "Processing add_affinity_group...", true)
  server_group_id = @task.get_option(:server_group_id) || ws_values[:server_group_id] rescue nil
  unless server_group_id.nil?
    clone_options = @task.get_option(:clone_options) || {}
    clone_options[:os_scheduler_hints] = { :group => "#{server_group_id}" }
    @task.set_option(:clone_options, clone_options)
    log(:info, "Provisioning object updated {:clone_options => #{@task.options[:clone_options].inspect}}")
  end
  log(:info, "Processing add_affinity_group...Complete", true)
end

def add_tenant(ws_values)
  # ensure that the cloud_tenant is set
  log(:info, "Processing add_tenant...", true)
  if @task.get_option(:cloud_tenant).blank?
    tenant_name = @task.get_option(:cloud_tenant) || ws_values[:cloud_tenant] rescue nil
    tenant_id = @task.get_option(:cloud_tenant_id) || ws_values[:cloud_tenant_id] rescue nil
    if tenant_name
      tenant = $evm.vmdb(:cloud_tenant).find_by_name(tenant_name)
      log(:info, "Using tenant: #{tenant.name} id: #{tenant.id} ems_ref: #{tenant.ems_ref}")
    elsif tenant_id
      tenant = $evm.vmdb(:cloud_tenant).find_by_id(tenant_id)
      log(:info, "Using tenant: #{tenant.name} id: #{tenant.id} ems_ref: #{tenant.ems_ref}")
    else
      tenant = $evm.vmdb(:cloud_tenant).find_by_name('admin')
      log(:info, "Using default tenant: #{tenant.name} id: #{tenant.id} ems_ref: #{tenant.ems_ref}")
    end
    @task.set_option(:cloud_tenant, [tenant.id, tenant.name])
    log(:info, "Provisioning object updated {:cloud_tenant => #{@task.options[:cloud_tenant].inspect}}")
  end
  log(:info, "Processing add_tenant...Complete", true)
end

def add_networks(ws_values)
  # ensure the cloud_network is set and look for additional networks to add to clone_options
  log(:info, "Processing add_networks...", true)
  clone_options = @task.get_option(:clone_options) || {}
  clone_options[:nics] = []
  cloud_network_id = @task.get_option(:cloud_network_0) || ws_values[:cloud_network_0] rescue nil
  cloud_network_id ||= @task.get_option(:cloud_network) || ws_values[:cloud_network] rescue nil
  n = 0
  while !cloud_network_id.nil? do
    log(:info, "cloud network id found: #{cloud_network_id}", true)
    cloud_network = $evm.vmdb(:cloud_network).find_by_id(cloud_network_id)
    break if cloud_network.nil?
    log(:info, "cloud network object found: #{cloud_network.inspect}", true)
    clone_options[:nics][n] = {}
    clone_options[:nics][n]['net_id'] = cloud_network['ems_ref'].to_s
    n +=1
    cloud_network_id = nil
    cloud_network_id ||= @task.get_option("cloud_network_#{n}".to_sym) || ws_values["cloud_network_#{n}".to_sym] rescue nil
  end
  log(:info, "Clone options updated with NIC information: #{clone_options.inspect}", true)
  @task.set_option(:clone_options, clone_options)
  log(:info, "Processing add_networks...Complete", true)
end

begin
  # Get provisioning object
  @task     = $evm.root['miq_provision']
  log(:info, "Provisioning ID:<#{@task.id}> Provision Request ID:<#{@task.miq_provision_request.id}> Provision Type: <#{@task.provision_type}>")

  # template  = @task.vm_template

  # Initialize ws_values
  ws_values = @task.options.fetch(:ws_values, {})

  add_tenant(ws_values)

  add_affinity_group(ws_values)

  add_networks(ws_values)

  # Log all of the options to the automation.log
  @task.options.each { |k,v| log(:info, "Provisioning Option Key(#{k.class}): #{k.inspect} Value: #{v.inspect}") }

  # Set Ruby rescue behavior
rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  @task.finished("#{err}") if @task && @task.respond_to?('finished')
  exit MIQ_ABORT
end

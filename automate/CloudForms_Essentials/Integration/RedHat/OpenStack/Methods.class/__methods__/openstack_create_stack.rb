=begin
  openstack_create_stack.rb

  Author: David Costakos <dcostako@redhat.com>, Kevin Morey <kevin@redhat.com>

  Description: This method creates an openstack stack
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

def parameters_to_hash(parameters)
  log(:info, "Generating hash from #{parameters}")
  array1 = parameters.split(";")
  hash = {}
  for item in array1
    key, value = item.split("=")
    hash["#{key}"] = "#{value}"
  end
  log(:info, "Returning parameter hash: #{hash.inspect}")
  return hash
end

def get_tenant()
  ws_values = @task.options.fetch(:ws_values, {})
  cloud_tenant_search_criteria = @task.get_option(:cloud_tenant_id) || ws_values[:cloud_tenant_id] ||
    @task.get_option(:cloud_tenant) || ws_values[:cloud_tenant] || 'admin' rescue 'admin'
  tenant = $evm.vmdb(:cloud_tenant).find_by_id(cloud_tenant_search_criteria) ||
    $evm.vmdb(:cloud_tenant).find_by_name(cloud_tenant_search_criteria) ||
    $evm.vmdb(:cloud_tenant).all.detect { |ct| ct.name.casecmp(cloud_tenant_search_criteria)==0 }
  return tenant
end

def get_fog_object(type='Compute', tenant='admin', endpoint='adminURL')
  require 'fog/openstack'
  (@provider.api_version == 'v2') ? (conn_ref = '/v2.0/tokens') : (conn_ref = '/v3/auth/tokens')
  (@provider.security_protocol == 'non-ssl') ? (proto = 'http') : (proto = 'https')
  
  connection_hash = {
    :openstack_api_key => @provider.authentication_password,
    :openstack_username => @provider.authentication_userid,
    :openstack_auth_url => "#{proto}://#{@provider.hostname}:#{@provider.port}#{conn_ref}",
    :openstack_tenant => tenant,
  }
  connection_hash[:openstack_endpoint_type] = endpoint if type == 'Identity'
  # if the openstack environment is using keystone v3, add two keys to hash and replace the auth_url
  if @provider.api_version == 'v3'
    connection_hash[:openstack_domain_name] = 'Default'
    connection_hash[:openstack_project_name] = tenant
    connection_hash[:openstack_auth_url] = "#{proto}://#{@provider.hostname}:35357/#{conn_ref}"
  end
  return Object::const_get("Fog").const_get("#{type}").const_get("OpenStack").new(connection_hash)
end

begin
  $evm.root.attributes.sort.each { |k, v| log(:info, "\t $evm.root Attribute - #{k}: #{v}")}

  case $evm.root['vmdb_object_type']
  when 'service_template_provision_task'
    # Executed via generic service catalog item
    @task = $evm.root['service_template_provision_task']
    @service = @task.destination
    log(:info, "Service: #{@service.name} id: #{@service.id} tasks: #{@task.miq_request_tasks.count}")
    @provider = get_provider
  when 'ext_management_system'
    # get vm from root
    @provider = $evm.root['ext_management_system']
  else
    exit MIQ_OK
  end

  tenant = get_tenant
  raise "no tenant found" if tenant.nil?

  customization_template = $evm.root['dialog_customization_template']
  customization_template = $evm.vmdb(:customization_template).find_by_id(heat_template_id) ||
    $evm.vmdb(:customization_template).find_by_id(customization_template)

  heat_template_yml   = customization_template.script rescue nil
  heat_template_yml ||= $evm.root['dialog_customization_template_script']
  raise "Heat template #{heat_template_yml} missing" if heat_template_yml.blank?

  log(:info, "Service Tags: #{@service.tags.inspect}")
  heat_tenant = @service.tags('tenant').first

  if heat_tenant.blank?
    heat_tenant   = @service.custom_get("TENANT_NAME") if tenant.blank?
    heat_tenant ||= $evm.root['dialog_tenant_name']
  end

  log(:info, "heat_tenant: #{heat_tenant}")
  raise "Missing heat_tenant: #{heat_tenant}"

  parameters = $evm.root['dialog_parameters']
  stack_name = $evm.root['dialog_stack_name'] || "Stack-#{$evm.root['user'].name}"

  log(:info, "Creating stack #{stack_name} in tenant #{heat_tenant}")
  log(:info, "Body:\n#{heat_template_yml}")
  log(:info, "Parameters: #{parameters}")

  options = { 'template' => heat_template_yml }
  options['parameters'] = parameters_to_hash(parameters) unless parameters.blank?

  openstack_orchestration = get_fog_object('Orchestration', tenant.name)

  stack_props = openstack_orchestration.create_stack(stack_name, options).body['stack']
  # Get a Stack Object
  stack = openstack_orchestration.stacks.find_by_id(stack_props['id'])
  raise "Missing stack id #{stack_props['id']}" if stack.nil?
  log(:info, "Stack: #{stack.inspect}")
  log(:info, "Stack created: #{stack.stack_status}/#{stack.stack_status_reason}")
  @service.name = "HEAT: #{stack.stack_name}"
  @service.description = "#{stack_props['id']}"
  @service_template_provision_task.set_option(:stack_id, stack_props['id'])
  @service_template_provision_task.set_option(:mid, mid)
  @service.custom_set("STACK_ID", stack_props['id'])
  @service.custom_set("MID", mid)
  @service.tag_assign("cloud_tenants/#{tenant}")

rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  @task.finished("#{err}") if @task
  exit MIQ_ABORT
end

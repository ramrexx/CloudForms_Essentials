=begin
  openstack_create_tenant.rb

  Author: Nate Stephany <nate@redhat.com>, Kevin Morey <kevin@redhat.com>

  Description: This method creates an openstack tenant and adds the CloudForms service
               account as an admin to the openstack tenant

  Mandatory dialog fields: tenant_name
  Optional dialog fields: tenant_description, admin_tenant, provider_id
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

def get_role_ids(openstack_keystone)
  roles = []
  openstack_keystone.list_roles[:body]["roles"].each { |role|
    log(:info, "role: #{role.inspect}")
    roles.push(role) if role["name"] == "admin" || role["name"] == "heat_stack_owner" || role["name"] == "_member_"
  }
  return roles
end

def get_provider(provider_id=nil)
  if provider_id.blank?
    $evm.root.attributes.detect { |k,v| provider_id = v if k.end_with?('provider_id') } rescue nil
  end
  provider = $evm.vmdb(:ManageIQ_Providers_Openstack_CloudManager).find_by_id(provider_id)
  if provider.nil?
    provider = $evm.vmdb(:ManageIQ_Providers_Openstack_CloudManager).first
    log(:info, "Found provider: #{provider.name} via default method") if provider
  else
    log(:info, "Found provider: #{provider.name} via provider_id: #{provider.id}") if provider
  end
  provider ? (return provider) : (return nil)
end

def process_tags( category, category_description, single_value, tag, tag_description )
  # Convert to lower case and replace all non-word characters with underscores
  category_name = category.to_s.downcase.gsub(/\W/, '_')
  tag_name = tag.to_s.downcase.gsub(/\W/, '_')
  log(:info, "Converted category name:<#{category_name}> Converted tag name: <#{tag_name}>")
  # if the category exists else create it
  unless $evm.execute('category_exists?', category_name)
    log(:info, "Category <#{category_name}> doesn't exist, creating category")
    $evm.execute('category_create', :name => category_name, :single_value => single_value, :description => "#{category_description}")
  end
  # if the tag exists else create it
  unless $evm.execute('tag_exists?', category_name, tag_name)
    log(:info, "Adding new tag <#{tag_name}> description <#{tag_description}> in Category <#{category_name}>")
    $evm.execute('tag_create', category_name, :name => tag_name, :description => "#{tag_description}")
  end
end

def update_status(options_hash)
  log(:info, "updating status: #{options_hash['status']}", true) unless options_hash['status'].blank?
  options_hash.each do |k,v|
    if @service
      # sets custom attributes on service, which are used later if we delete the tenant/service through CF
      @service.custom_set(k, v.to_s)
      # check for normalized tagging of tenant name on the service object
      unless @service.tagged_with?('tenant', options_hash['tenant_name'].to_s.downcase.gsub(/\W/, '_'))
        @service.tag_assign("tenant/#{options_hash['tenant_name'].to_s.downcase.gsub(/\W/, '_')}")
        log(:info, "Tagged Service: #{@service.tags.inspect}")
      end
    end
  end
  $evm.set_state_var(:options_hash, options_hash)
  log(:info, "Workspace variable updated {:options_hash=>#{$evm.get_state_var(:options_hash)}")
end

begin
  $evm.root.attributes.sort.each { |k, v| log(:info, "\t $evm.root Attribute - #{k}: #{v}")}

  case $evm.root['vmdb_object_type']
  when 'service_template_provision_task'
    # Executed via generic service catalog item
    @task = $evm.root['service_template_provision_task']
    @service = @task.destination
    log(:info, "Service: #{@service.name} id: #{@service.id} tasks: #{@task.miq_request_tasks.count}")
    # options_hash is used to collect information along the way for reuse
    $evm.get_state_var(:options_hash).blank? ? (options_hash = {}) : (options_hash = $evm.get_state_var(:options_hash))
    # giving the option to set these in the dialog or rely on more default values
    admin_tenant = $evm.root['dialog_admin_tenant'] || options_hash['admin_tenant'] || 'admin'
    provider_id =  $evm.root['dialog_provider_id'] || options_hash['provider_id']
    # this must be collected in dialog
    tenant_name =  $evm.root['dialog_tenant_name'] || options_hash['tenant_name']
    # this can be collected in dialog, but is not mandatory
    tenant_description = $evm.root['dialog_tenant_description'] || options_hash['tenant_description']

    @provider = get_provider(provider_id)
  else
    exit MIQ_OK
  end

  raise "missing provider: #{@provider}" if @provider.nil?

  options_hash['admin_tenant'] = admin_tenant
  log(:info, "provider: #{@provider.name} admin_tenant: #{admin_tenant}")
  options_hash['provider_id'] = @provider.id

  openstack_keystone = get_fog_object('Identity', admin_tenant)

  # Checks with OpenStack provider to ensure this tenant name is not already in use
  # If it is, a new name will be created by appending 3 integers to end of requested name
  if openstack_keystone.tenants.detect { |t| t.name == tenant_name } 
    for i in (1..999)
      tmp_tenant_name = "#{tenant_name}" + "#{i}".rjust(3, '0')
      log(:info, "Checking for existence of tenant: #{tmp_tenant_name}")
      unless openstack_keystone.list_tenants.body["tenants"].detect { |t| t.name == tmp_tenant_name }
        tenant_name = tmp_tenant_name
        break
      end
    end
  end

  # Create the new tenant
  new_tenant_hash = openstack_keystone.create_tenant(
    {
      :description => "CloudForms created project #{tenant_name}  #{tenant_description}",
      :enabled => true,
      :name => tenant_name
    }
  )[:body]['tenant']
  log(:info, "Successfully created tenant #{new_tenant_hash.inspect}")

  # Update the options_hash with data from newly created tenant
  options_hash['tenant_id'] = new_tenant_hash['id']
  options_hash['tenant_name'] = new_tenant_hash['name']
  options_hash['tenant_description'] = new_tenant_hash['description']

  # add cloudforms keystone userid to the tenant so that we can pick it up on the next provider refresh
  # identify the user cloudforms is using to connect to provider
  openstack_admin = openstack_keystone.list_users[:body]["users"].detect { |user| user["name"] == "#{@provider.authentication_userid}" }
  log(:info, "openstack_admin: #{openstack_admin.inspect}")
  options_hash['openstack_admin_id'] = openstack_admin['id']

  # get the IDs of the roles that we want admin user to have
  net_tenant_roles = get_role_ids(openstack_keystone)
  log(:info, "roles: #{net_tenant_roles.inspect}")
  # add the user to the tenant with the roles just identified
  net_tenant_roles.each { |role|
    openstack_keystone.create_user_role(new_tenant_hash["id"], openstack_admin["id"], role["id"])
  }
  log(:info, "User Roles Applied: #{openstack_keystone.list_roles_for_user_on_tenant(new_tenant_hash["id"], openstack_admin["id"]).inspect}")
  # tage the service with a tag from the tenant category
  process_tags('tenant', "Tenant", false, new_tenant_hash["name"], new_tenant_hash["name"])
  options_hash['status'] = "Created Tenant #{new_tenant_hash["name"]}"
  # refresh the provider to pick up the new cloud_tenant
  @provider.refresh
  update_status(options_hash)

  new_service_name = "Openstack Tenant - #{tenant_name}"
  @service.name = new_service_name

rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

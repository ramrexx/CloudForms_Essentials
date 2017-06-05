=begin
  InspectMe.rb

  Author: Kevin Morey <kevin@redhat.com>

  Description: This method dump the objects in storage to the automation.log
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

def dump_root()
  log(:info, "Begin $evm.root.attributes")
  $evm.root.attributes.sort.each { |k, v| log(:info, "\t Attribute: #{k} = #{v}")}
  log(:info, "End $evm.root.attributes")
  log(:info, "")
end

def dump_attributes(object_type, object)
  log(:info, "Begin #{object_type}.attributes")
  if object.respond_to?('attributes')
    if $evm.root['user'].current_group.description == 'EvmGroup-super_administrator'
      log(:info, "\t #{object.name} - Attribute: 'authentication_userid' = #{object.authentication_userid.inspect}") if object.respond_to?('authentication_userid')
      log(:info, "\t #{object.name} - Attribute: 'authentication_password_encrypted' = #{object.authentication_password_encrypted.inspect}") if object.respond_to?('authentication_password_encrypted')
      log(:info, "\t #{object.name} - Attribute: 'authentication_password' = #{object.authentication_password.inspect}") if object.respond_to?('authentication_password')
    end
    object.attributes.sort.each { |k, v| log(:info, "\t #{object.name rescue object.description rescue nil} - Attribute: #{k.inspect} = #{v.inspect} (type: #{v.class})") }
  elsif object.respond_to?('each')
    object.each { |obj| obj.attributes.sort.each { |k,v| log(:info, "\t #{obj.name rescue obj.description rescue nil} - Attribute: #{k.inspect} = #{v.inspect} (type: #{v.class})")}}
  elsif object.respond_to?('count')
    log(:info, "\t #{object_type}: #{object.count}")
  elsif object_type == 'current_object'
    log(:info, "\t #{object.name} - Attribute: 'class_name' = #{object.class_name.inspect}")
    log(:info, "\t #{object.name} - Attribute: 'current_message' = #{object.current_message.inspect}")
    log(:info, "\t #{object.name} - Attribute: 'current_field_name' = #{object.current_field_name.inspect}")
    log(:info, "\t #{object.name} - Attribute: 'current_field_type' = #{object.current_field_type.inspect}")
    log(:info, "\t #{object.name} - Attribute: 'instance_name' = #{object.instance_name.inspect}")
    log(:info, "\t #{object.name} - Attribute: 'namespace' = #{object.namespace.inspect}")
    log(:info, "\t #{object.name} - Attribute: 'children' = #{object.children.inspect}")
  else
    log(:info, "\t #{object_type}: #{object.inspect}")
  end
  log(:info, "End #{object_type}.attributes")
  log(:info, "")
end

def dump_associations(object_type, object)
  log(:info, "Begin #{object_type}.associations")
  if object.respond_to?('associations')
    object.associations.sort.each { |assc| log(:info, "\t #{object.name rescue object.description rescue nil} - Association: #{assc}") }
  else
    object.each {|obj| obj.associations.sort.each { |assc| log(:info, "\t #{object.name rescue object.description rescue nil} - Association: #{assc}") } }
  end
  log(:info, "End #{object_type}.associations")
  log(:info, "")
end

def dump_tags(object_type, object)
  log(:info, "Begin #{object_type}.tags")
  if object.respond_to?('tags')
    object.tags.sort.each do |tag_element|
      tag_text = tag_element.split('/')
      log(:info, "\t #{object.name rescue object.description rescue nil} - Category: #{tag_text.first.inspect} Tag: #{tag_text.last.inspect}")
    end
  else
    object.each do |obj|
      obj.tags.sort.each do |tag_element|
        tag_text = tag_element.split('/')
        log(:info, "\t #{obj.name rescue obj.description rescue nil} - Category: #{tag_text.first.inspect} Tag: #{tag_text.last.inspect}")
      end
    end
  end
  log(:info, "End #{object_type}.tags")
  log(:info, "")
end

def dump_virtual_columns(object_type, object)
  log(:info, "Begin #{object_type}.virtual_column_names")
  if object.respond_to?('virtual_column_names')
    object.virtual_column_names.sort.each { |vcn| log(:info, "\t #{object.name rescue object.description rescue nil} - Virtual Column: #{vcn} = #{object.send(vcn).inspect}") }
  else
    object.each {|obj| obj.virtual_column_names.sort.each { |vcn| log(:info, "\t #{obj.name rescue obj.description rescue nil} - Virtual Column: #{vcn} = #{obj.send(vcn).inspect}") } }
  end
  log(:info, "End #{object_type}.virtual_column_names")
  log(:info, "")
end

def dump_current_object()
  object_type = 'current_object'
  object = $evm.current_object
  dump_attributes(object_type, object)
end

# CloudForms Server Information
def dump_miq_server()
  object_type = 'miq_server'
  object = $evm.root["#{object_type}"]
  dump_attributes(object_type, object)
  dump_associations(object_type, object)
  dump_virtual_columns(object_type, object)
end

# User Information
def dump_user()
  object_type = 'user'
  object = $evm.root["#{object_type}"]
  dump_attributes(object_type, object)
  dump_associations(object_type, object)
  dump_tags(object_type, object)
  dump_virtual_columns(object_type, object)
  dump_attributes("#{object_type}.miq_requests.count", object.miq_requests.count) if object.respond_to?('miq_requests')
end

# Group Information
def dump_current_group()
  object_type = 'current_group'
  object = $evm.root['user'].current_group
  dump_attributes(object_type, object)
  dump_associations(object_type, object)
  dump_tags(object_type, object)
  dump_virtual_columns(object_type, object)
  dump_attributes("#{object_type}.vms.count", object.vms.count) if object.respond_to?('vms')
  dump_attributes("#{object_type}.users.count", object.users.count) if object.respond_to?('users')
end

# Cluster Information
def dump_ems_cluster()
  object_type = $evm.root['vmdb_object_type']
  object = $evm.vmdb('ems_cluster').find_by_id($evm.root['ems_cluster_id'])
  dump_attributes(object_type, object)
  dump_associations(object_type, object)
  dump_tags(object_type, object)
  dump_virtual_columns(object_type, object)

  dump_attributes("#{object_type}.ext_management_system", object.ext_management_system) if object.respond_to?('ext_management_system')
  dump_attributes("#{object_type}.hosts", object.hosts) if object.respond_to?('hosts')
  dump_attributes("#{object_type}.default_resource_pool", object.default_resource_pool) if object.respond_to?('default_resource_pool')
  dump_attributes("#{object_type}.parent_folder", object.parent_folder) if object.respond_to?('parent_folder')
  dump_attributes("#{object_type}.vms.count", object.vms.count) if object.respond_to?('vms')
  dump_attributes("#{object_type}.resource_pools", object.resource_pools) if object.respond_to?('resource_pools')
end

# Provider Information
def dump_ext_management_system()
  object_type = $evm.root['vmdb_object_type']
  object = $evm.vmdb('ext_management_system').find_by_id($evm.root['ext_management_system_id'])
  dump_attributes(object_type, object)
  dump_associations(object_type, object)
  dump_tags(object_type, object)
  dump_virtual_columns(object_type, object)

  dump_attributes("#{object_type}.availability_zones", object.availability_zones) if object.respond_to?('availability_zones')
  dump_associations("#{object_type}.availability_zones", object.availability_zones) if object.respond_to?('availability_zones')
  dump_virtual_columns("#{object_type}.availability_zones", object.availability_zones) if object.respond_to?('availability_zones')
  dump_attributes("#{object_type}.cloud_networks", object.cloud_networks) if object.respond_to?('cloud_networks')
  dump_associations("#{object_type}.cloud_networks", object.cloud_networks) if object.respond_to?('cloud_networks')
  dump_attributes("#{object_type}.cloud_resource_quotas", object.cloud_resource_quotas) if object.respond_to?('cloud_resource_quotas')
  dump_associations("#{object_type}.cloud_resource_quotas", object.cloud_resource_quotas) if object.respond_to?('cloud_resource_quotas')
  dump_attributes("#{object_type}.cloud_tenants", object.cloud_tenants) if object.respond_to?('cloud_tenants')
  dump_associations("#{object_type}.cloud_tenants", object.cloud_tenants) if object.respond_to?('cloud_tenants')
  dump_attributes("#{object_type}.ems_clusters", object.ems_clusters) if object.respond_to?('ems_clusters')
  dump_associations("#{object_type}.ems_clusters", object.ems_clusters) if object.respond_to?('ems_clusters')
  dump_attributes("#{object_type}.ems_folders", object.ems_folders) if object.respond_to?('ems_folders')
  dump_associations("#{object_type}.ems_folders", object.ems_folders) if object.respond_to?('ems_folders')
  dump_attributes("#{object_type}.flavors", object.flavors) if object.respond_to?('flavors')
  dump_attributes("#{object_type}.floating_ips", object.floating_ips) if object.respond_to?('floating_ips')
  dump_associations("#{object_type}.floating_ips", object.floating_ips) if object.respond_to?('floating_ips')
  dump_attributes("#{object_type}.hosts", object.hosts) if object.respond_to?('hosts')
  dump_attributes("#{object_type}.key_pairs", object.key_pairs) if object.respond_to?('key_pairs')
  dump_attributes("#{object_type}.resource_pools", object.resource_pools) if object.respond_to?('resource_pools')
  dump_attributes("#{object_type}.security_groups", object.security_groups) if object.respond_to?('security_groups')
  dump_attributes("#{object_type}.storages", object.storages) if object.respond_to?('storages')
  dump_attributes("#{object_type}.vms.count", object.vms.count) if object.respond_to?('vms')
end

# Host Information
def dump_host()
  object_type = $evm.root['vmdb_object_type']
  object = $evm.vmdb('host').find_by_id($evm.root['host_id'])
  dump_attributes(object_type, object)
  dump_associations(object_type, object)
  dump_tags(object_type, object)
  dump_virtual_columns(object_type, object)

  dump_attributes("#{object_type}.datacenter", object.datacenter) if object.respond_to?('datacenter')
  dump_attributes("#{object_type}.ems_cluster", object.ems_cluster) if object.respond_to?('ems_cluster')
  dump_attributes("#{object_type}.ems_folder", object.ems_folder) if object.respond_to?('ems_folder')
  dump_attributes("#{object_type}.ext_management_system", object.ext_management_system) if object.respond_to?('ext_management_system')
  dump_attributes("#{object_type}.guest_applications", object.guest_applications) if object.respond_to?('guest_applications')
  dump_attributes("#{object_type}.hardware", object.hardware) if object.respond_to?('hardware')
  dump_associations("#{object_type}.hardware", object.hardware) if object.respond_to?('hardware')
  dump_attributes("#{object_type}.hardware.guest_devices", object.hardware.guest_devices) if object.hardware.respond_to?('guest_devices')
  dump_attributes("#{object_type}.hardware.ports", object.hardware.ports) if object.hardware.respond_to?('ports')
  dump_attributes("#{object_type}.lans", object.lans) if object.respond_to?('lans')
  dump_attributes("#{object_type}.operating_system", object.operating_system) if object.respond_to?('operating_system')
  dump_attributes("#{object_type}.switches", object.switches) if object.respond_to?('switches')
  dump_attributes("#{object_type}.storages", object.storages) if object.respond_to?('storages')
  dump_attributes("#{object_type}.vms.count", object.vms.count) if object.respond_to?('vms')
end

# Service Information
def dump_service()
  object_type = $evm.root['vmdb_object_type']
  object = $evm.vmdb('service').find_by_id($evm.root['service_id'])
  dump_attributes(object_type, object)
  dump_associations(object_type, object)
  dump_tags(object_type, object)
  dump_virtual_columns(object_type, object)

  dump_attributes("#{object_type}.vms.count", object.vms.count) if object.respond_to?('vms')
  dump_attributes("#{object_type}.direct_vms", object.direct_vms) if object.respond_to?('direct_vms')
  dump_attributes("#{object_type}.indirect_vms", object.indirect_vms) if object.respond_to?('indirect_vms')
  dump_attributes("#{object_type}.all_service_children", object.all_service_children) if object.respond_to?('all_service_children')
  dump_attributes("#{object_type}.direct_service_children", object.direct_service_children) if object.respond_to?('direct_service_children')
end

# CatalogItem Information
def dump_service_template()
  object_type = $evm.root['vmdb_object_type']
  object = $evm.vmdb('service_template').find_by_id($evm.root['service_template_id'])
  dump_attributes(object_type, object)
  dump_associations(object_type, object)
  dump_tags(object_type, object)
  dump_virtual_columns(object_type, object)

  dump_attributes("#{object_type}.service_resources", object.service_resources) if object.respond_to?('service_resources')
  dump_attributes("#{object_type}.service_templates", object.service_templates) if object.respond_to?('service_templates')
  dump_attributes("#{object_type}.services", object.services) if object.respond_to?('services')
end

# Storage Information
def dump_storage()
  object_type = $evm.root['vmdb_object_type']
  object = $evm.vmdb('storage').find_by_id($evm.root['storage_id'])
  dump_attributes(object_type, object)
  dump_associations(object_type, object)
  dump_tags(object_type, object)
  dump_virtual_columns(object_type, object)

  dump_attributes("#{object_type}.ext_management_system", object.ext_management_system) if object.respond_to?('ext_management_system')
  dump_attributes("#{object_type}.hosts.count", object.hosts.count) if object.respond_to?('hosts')
  dump_attributes("#{object_type}.unregistered_vms.count", object.unregistered_vms.count) if object.respond_to?('unregistered_vms')
  dump_attributes("#{object_type}.vms.count", object.vms.count) if object.respond_to?('vms')
end

# VM Information
def dump_vm()
  object_type = $evm.root['vmdb_object_type']
  object = $evm.vmdb('vm_or_template').find_by_id($evm.root['vm_id'])
  dump_attributes(object_type, object)
  dump_associations(object_type, object)
  dump_tags(object_type, object)
  dump_virtual_columns(object_type, object)

  dump_attributes("#{object_type}.datacenter", object.datacenter) if object.respond_to?('datacenter')
  dump_associations("#{object_type}.datacenter", object.datacenter) if object.respond_to?('datacenter')
  dump_attributes("#{object_type}.direct_service", object.direct_service) if object.respond_to?('direct_service')
  dump_attributes("#{object_type}.ems_cluster", object.ems_cluster) if object.respond_to?('ems_cluster')
  dump_attributes("#{object_type}.ems_folder", object.ems_folder) if object.respond_to?('ems_folder')
  dump_attributes("#{object_type}.ext_management_system", object.ext_management_system) if object.respond_to?('ext_management_system')
  dump_associations("#{object_type}.ext_management_system", object.ext_management_system) if object.respond_to?('ext_management_system')
  dump_attributes("#{object_type}.guest_applications", object.guest_applications) if object.respond_to?('guest_applications')
  dump_attributes("#{object_type}.hardware", object.hardware)
  dump_associations("#{object_type}.hardware", object.hardware)
  dump_attributes("#{object_type}.hardware.nics", object.hardware.nics) if object.hardware.respond_to?('nics')
  dump_attributes("#{object_type}.hardware.ports", object.hardware.ports) if object.hardware.respond_to?('ports')
  dump_attributes("#{object_type}.hardware.storage_adapters", object.hardware.storage_adapters) if object.hardware.respond_to?('storage_adapters')
  dump_attributes("#{object_type}.host", object.host) if object.respond_to?('host')
  dump_attributes("#{object_type}.miq_provision", object.miq_provision) if object.respond_to?('miq_provision')
  dump_attributes("#{object_type}.miq_provision.miq_provision_request", object.miq_provision.miq_provision_request) unless object.miq_provision.nil?
  dump_attributes("#{object_type}.operating_system", object.operating_system) if object.respond_to?('operating_system')
  dump_attributes("#{object_type}.owner", object.owner) if object.respond_to?('owner')
  dump_attributes("#{object_type}.resource_pool", object.resource_pool) if object.respond_to?('resource_pool')
  dump_attributes("#{object_type}.service", object.service) if object.respond_to?('service')
  dump_attributes("#{object_type}.snapshots", object.snapshots) if object.respond_to?('snapshots')
  dump_attributes("#{object_type}.storage", object.storage) if object.respond_to?('storage')
end

# dump root
dump_root()

# dump_current_object
dump_current_object()

# dump miq_server
dump_miq_server()

# dump user
dump_user()

# dump current_group
dump_current_group()

begin

  case $evm.root['vmdb_object_type']
  when 'ems_cluster' then dump_ems_cluster()
  when 'ext_management_system' then dump_ext_management_system()
  when 'host' then dump_host()
  when 'service' then dump_service()
  when 'service_template' then dump_service_template()
  when 'storage' then dump_storage()
  when 'vm' then dump_vm()
  end

rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

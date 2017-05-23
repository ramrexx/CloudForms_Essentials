=begin
  build_vm_provision_request.rb

  Author: Kevin Morey <kevin@redhat.com>

  Description: This method Performs the following functions:
   1. YAML load the Service Dialog Options from @task.get_option(:parsed_dialog_options))
   2. override service attributes
   3. Set tags on the service
   4. Gather provisioning options
   5. Launch VMProvisionRequest with options, tags and args

  Uses: Simple method to kick off a provisioning request from the one of the following:
    a) Generic Service Catalog Item that provisions one or many VMs into a service
    b) Service Button for the purpose of provisioning VMs to an existing service
    c) Automation request (API) driven for the purpose of provisioning VMs
    d) VM driven from a button, Policy or Alert event for Flexing

  Important: The dialog_parser MUST run prior to this in order to populate the dialog information correctly

  Inputs: dialog_option_[0-9]_guid, dialog_option_[0-9]_flavor, dialog_tag_[0-9]_environment, etc...
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

# create the categories and tags
def create_tags(category, single_value=true, tag)
  log(:info, "Processing create_tags...", true)
  # Convert to lower case and replace all non-word characters with underscores
  category_name = category.to_s.downcase.gsub(/\W/, '_')
  tag_name = tag.to_s.downcase.gsub(/\W/, '_')

  unless $evm.execute('category_exists?', category_name)
    log(:info, "Category #{category_name} doesn't exist, creating category")
    $evm.execute('category_create', :name=>category_name, :single_value=>single_value, :description=>"#{category}")
  end
  # if the tag exists else create it
  unless $evm.execute('tag_exists?', category_name, tag_name)
    log(:info, "Adding new tag #{tag_name} in Category #{category_name}")
    $evm.execute('tag_create', category_name, :name => tag_name, :description => "#{tag}")
  end
  log(:info, "Processing create_tags...Complete", true)
end

# Override service attributes (service_name, service_description, service_retirement)
def override_service_attribute(dialogs_options_hash, attr_name)
  service_attr_name = "service_#{attr_name}".to_sym
  log(:info, "Processing override_attribute for #{service_attr_name}...", true)
  attr_value = dialogs_options_hash.fetch(service_attr_name, nil)
  attr_value = "#{@service.name}-#{Time.now.strftime('%Y%m%d-%H%M%S')}" if attr_name == 'name' && attr_value.nil?
  log(:info, "Setting service attribute: #{attr_name} to: #{attr_value}")
  @service.send("#{attr_name}=", attr_value)
  log(:info, "Processing override_attribute for #{service_attr_name}...Complete", true)
end

def process_tag(tag_category, tag_value)
  return if tag_value.blank?
  create_tags(tag_category, true, tag_value)
end

# service_tagging - tag the service with tags in tags_hash
def tag_service(tags_hash)
  log(:info, "Processing tag_service...", true)
  tags_hash.each do |key, value|
    log(:info, "Processing tag: #{key.inspect} value: #{value.inspect}")
    tag_category = key.downcase
    Array.wrap(value).each do |tag_entry|
      process_tag(tag_category, tag_entry.downcase)
      log(:info, "Assigning Tag: {#{tag_category}=>#{tag_entry}} to Service: #{@service.name}")
      @service.tag_assign("#{tag_category}/#{tag_entry}")
    end
    log(:info, "Processing tag_service...Complete", true)
  end
end

def dialog_parser_error
  raise 'Error loading dialog options'
end

def yaml_data(option)
  @task.get_option(option).nil? ? nil : YAML.load(@task.get_option(option))
end

# fix_dialog_tags_hash to allow for support of Tag Control items in dialogs.  Previously, the Tag Control would
# push values in as an array, which is not supported.  The fix_dialog_tag_hash parsed the dialog_tags_hash and changes
# all array values to strings.
def fix_dialog_tags_hash(dialog_tags_hash)
  unless dialog_tags_hash.empty?
    dialog_tags_hash.each do |build_num,build_tags_hash|
      build_tags_hash.each do |k,v|
        if v.is_a?(Array)
          log(:info, "fix_dialog_tags_hash: Build #{build_num}: updating key <#{k}> with array value <#{v}> to <#{v.first}>")
          build_tags_hash[k] = v.first if v.is_a?(Array)
        end
      end
    end
  end
  dialog_tags_hash
end

# check to ensure that dialog_parser has ran
def parsed_dialog_information
  dialog_options_hash = yaml_data(:parsed_dialog_options)
  dialog_tags_hash = yaml_data(:parsed_dialog_tags)
  if dialog_options_hash.blank? && dialog_tags_hash.blank?
    log(:info, "Instantiating dialog_parser to populate dialog options")
    $evm.instantiate('/Service/Provisioning/StateMachines/Methods/DialogParser')
    dialog_options_hash = yaml_data(:parsed_dialog_options)
    dialog_tags_hash = yaml_data(:parsed_dialog_tags)
    dialog_parser_error if dialog_options_hash.blank? && dialog_tags_hash.blank?
  end
  log(:info, "dialog_options_hash: #{dialog_options_hash.inspect}")
  log(:info, "dialog_tags_hash: #{dialog_tags_hash.inspect}")
  return dialog_options_hash, fix_dialog_tags_hash(dialog_tags_hash)
end

def merge_service_item_dialog_values(build, dialogs_hash)
  merged_hash = Hash.new { |h, k| h[k] = {} }
  if dialogs_hash[0].nil?
    merged_hash = dialogs_hash[build] || {}
  else
    merged_hash = dialogs_hash[0].merge(dialogs_hash[build] || {})
  end
  merged_hash
end

# merge dialog information
def merge_dialog_information(build, dialog_options_hash, dialog_tags_hash)
  merged_options_hash = merge_service_item_dialog_values(build, dialog_options_hash)
  merged_tags_hash = merge_service_item_dialog_values(build, dialog_tags_hash)
  log(:info, "build: #{build} merged_options_hash: #{merged_options_hash.inspect}")
  log(:info, "build: #{build} merged_tags_hash: #{merged_tags_hash.inspect}")
  return merged_options_hash, merged_tags_hash
end

def get_array_of_builds(dialogs_options_hash)
  builds = []
  dialogs_options_hash.each do |build, options|
    next if build.zero?
    builds << build
  end
  builds.sort
end

# look at the users current group to get the rbac tag filters applied to that group
def get_current_group_rbac_array
  @rbac_array = []
  unless @user.current_group.filters.blank?
    @user.current_group.filters['managed'].flatten.each do |filter|
      next unless /(?<category>\w*)\/(?<tag>\w*)$/i =~ filter
      @rbac_array << {category=>tag}
    end
  end
  log(:info, "@user: #{@user.userid} RBAC filters: #{@rbac_array}")
  @rbac_array
end

# using the rbac filters check to ensure that templates, clusters, security_groups, etc... are tagged
def object_eligible?(obj)
  @rbac_array.each do |rbac_hash|
    rbac_hash.each do |rbac_category, rbac_tags|
      Array.wrap(rbac_tags).each {|rbac_tag_entry| return false unless obj.tagged_with?(rbac_category, rbac_tag_entry) }
    end
    true
  end
end

# determine who the requesting user is
def get_requester(build, merged_options_hash, merged_tags_hash)
  log(:info, "Processing get_requester...", true)
  @user = $evm.vmdb('user').find_by_id(merged_options_hash[:user_id]) ||
    $evm.root['user']
  merged_options_hash[:user_name]        = @user.userid
  merged_options_hash[:owner_first_name] = @user.first_name ? @user.first_name : 'Cloud'
  merged_options_hash[:owner_last_name]  = @user.last_name ? @user.last_name : 'Admin'
  merged_options_hash[:owner_email]      = @user.email ? @user.email : $evm.object['to_email_address']
  log(:info, "Build: #{build} - User: #{merged_options_hash[:user_name]} " \
      "email: #{merged_options_hash[:owner_email]}")
  # Stuff the current group information
  merged_options_hash[:group_id] = @user.current_group.id
  merged_options_hash[:group_name] = @user.current_group.description
  log(:info, "Build: #{build} - Group: #{merged_options_hash[:group_name]} " \
      "id: #{merged_options_hash[:group_id]}")

  log(:info, "Processing get_requester...Complete", true)
end

def get_template(build, merged_options_hash, merged_tags_hash)
  log(:info, "Processing get_template...", true)
  template_search_by_guid     = merged_options_hash[:guid]
  template_search_by_name     = merged_options_hash[:template] || merged_options_hash[:name]
  template_search_by_product  = merged_options_hash[:product]
  template_search_by_os       = merged_options_hash[:os]

  templates = []
  vmdb_table = :miq_template

  if template_search_by_guid && templates.blank?
    log(:info, "Searching for templates tagged with #{@rbac_array} that " \
        "match guid: #{template_search_by_guid}")
    templates = $evm.vmdb(vmdb_table).all.select do |t|
      object_eligible?(t) && t.ext_management_system && t.guid == template_search_by_guid
    end
  end
  if template_search_by_name && templates.blank?
    log(:info, "Searching for templates tagged with #{@rbac_array} that are " \
        "named: #{template_search_by_name}")
    templates = $evm.vmdb(vmdb_table).all.select do |t|
      object_eligible?(t) && t.ext_management_system && t.name == template_search_by_name
    end
  end
  if template_search_by_product && templates.blank?
    product_category = 'product'
    log(:info, "Searching for templates tagged with #{@rbac_array} and " \
        "{:#{product_category}=>#{template_search_by_product}}")
    templates = $evm.vmdb(vmdb_table).all.select do |t|
      object_eligible?(t) && t.ext_management_system && t.tagged_with?(product_category, template_search_by_product)
    end
  end

  if template_search_by_os && templates.blank?
    case merged_tags_hash[:environment]
    when 'dev';  vmdb_table = :ManageIQ_Providers_Openstack_CloudManager_Template
    when 'prod'; vmdb_table = :ManageIQ_Providers_Vmware_InfraManager_Template
    when 'test'; vmdb_table = :ManageIQ_Providers_Amazon_CloudManager_Template
    when 'qa';   vmdb_table = :ManageIQ_Providers_Redhat_InfraManager_Template
    end
    os_category = 'os'
    log(:info, "Searching for templates tagged with #{@rbac_array} and "\
        "{#{os_category.to_sym}=>#{template_search_by_os}}")
    templates = $evm.vmdb(vmdb_table).all.select do |t|
      object_eligible?(t) && t.ext_management_system && t.tagged_with?(os_category, template_search_by_os)
    end
  end
  raise "No templates found for user: #{@user.userid} RBAC: #{@rbac_array}" if templates.blank?

  # sort templates by the number of vms per provider to load-balance across different providers
  templates.sort! { |t1, t2| t1.ext_management_system.vms.count <=> t2.ext_management_system.vms.count }

  # get the first template in the list
  @template = templates.first
  log(:info, "Build: #{build} - template: #{@template.name} guid: #{@template.guid} " \
      "on provider: #{@template.ext_management_system.name}")
  merged_options_hash[:name] = @template.name
  merged_options_hash[:guid] = @template.guid
  log(:info, "Processing get_template...Complete", true)
end

def get_cloud_tenant(build, merged_options_hash, merged_tags_hash)
  log(:info, "Processing get_cloud_tenant...", true)
  case @template.vendor.downcase
  when 'openstack'
    provider = @template.ext_management_system
    cloud_tenant_search_criteria  = merged_options_hash[:cloud_tenant] || merged_options_hash[:cloud_tenant_id] || 'admin'
    @tenant = provider.cloud_tenants.detect {|ct| object_eligible?(ct) && ct.id == cloud_tenant_search_criteria.to_i } ||
      provider.cloud_tenants.detect {|ct| object_eligible?(ct) && ct.name.downcase == cloud_tenant_search_criteria.downcase }

    if @tenant
      tenant_name = @tenant.name.downcase
      merged_options_hash[:cloud_tenant]    = @tenant.id
      merged_options_hash[:cloud_tenant_id] = @tenant.id
      merged_tags_hash[:cloud_tenant]       = tenant_name
      log(:info, "Build: #{build} - tenant: #{merged_tags_hash[:cloud_tenant]} " \
          "id: #{merged_options_hash[:cloud_tenant]}")
    end
  end
  log(:info, "Processing get_cloud_tenant...Complete", true)
end

def get_provision_type(build, merged_options_hash, merged_tags_hash)
  log(:info, "Processing get_provision_type...", true)
  case @template.vendor.downcase
  when 'vmware'
    # Valid types for vmware:  vmware, pxe, netapp_rcu
    if merged_options_hash[:provision_type].blank?
      merged_options_hash[:provision_type] = 'vmware'
    end
  when 'redhat'
    # Valid types for rhev: iso, pxe, native_clone
    if merged_options_hash[:provision_type].blank?
      merged_options_hash[:provision_type] = 'native_clone'
    end
  end
  if merged_options_hash[:provision_type]
    log(:info, "Build: #{build} - provision_type: #{merged_options_hash[:provision_type]}")
  end
  log(:info, "Processing get_provision_type...Complete", true)
end

def get_vm_name(build, merged_options_hash, merged_tags_hash)
  log(:info, "Processing get_vm_name", true)
  new_vm_name = merged_options_hash[:vm_name] || merged_options_hash[:vm_target_name]
  if new_vm_name.blank?
    merged_options_hash[:vm_name] = 'changeme'
  else
    unless $evm.vmdb(:vm_or_template).find_by_name(merged_options_hash[:vm_name]).blank?
      # Loop through 000-999 and look to see if the vm_name already exists in the vmdb to avoid collisions
      for i in (1..999)
        proposed_vm_name = "#{merged_options_hash[:vm_name]}#{i.to_s.rjust(2, "0")}"
        log(:info, "Checking for existence of vm: #{proposed_vm_name}")
        break if $evm.vmdb(:vm_or_template).find_by_name(proposed_vm_name).blank?
      end
      merged_options_hash[:vm_name] = proposed_vm_name
      merged_options_hash[:linux_host_name] = proposed_vm_name
    end
  end
  log(:info, "Build: #{build} - VM Name: #{merged_options_hash[:vm_name]}")
  log(:info, "Processing get_vm_name...Complete", true)
end

def get_network(build, merged_options_hash, merged_tags_hash)
  log(:info, "Processing get_network...", true)
  provider = @template.ext_management_system

  case @template.vendor.downcase
  when 'vmware'
    if merged_options_hash[:vlan].blank?
      case merged_tags_hash[:environment]
      when 'dev', 'test'; merged_options_hash[:vlan] = 'VM Network'
      when 'stage', 'prod'; merged_options_hash[:vlan] = 'VM Network'
      else
        # merged_options_hash[:vlan] = 'dvs_Production - 10.1.45.0/24'
        merged_options_hash[:vlan] = 'VM Network'
      end
      log(:info, "Build: #{build} - vlan: #{merged_options_hash[:vlan]}")
    end
  when 'redhat'
    if merged_options_hash[:vlan].blank?
      case merged_tags_hash[:environment]
      when 'dev', 'test';   merged_options_hash[:vlan] = 'rhevm'
      when 'stage', 'prod'; merged_options_hash[:vlan] = 'rhevm'
      else
        # Set a default vlan here
        merged_options_hash[:vlan] = 'rhevm'
      end
      log(:info, "Build: #{build} - vlan: #{merged_options_hash[:vlan]}")
    end
  when 'amazon'
  when 'openstack'
    # get the key_pair from the provider because we do not have a relationship to tenant projects yet
    if merged_options_hash[:guest_access_key_pair].blank?
      key_pair = provider.key_pairs.first
    else
      key_pair = provider.key_pairs.detect { |kp| kp.name == merged_options_hash[:guest_access_key_pair] } ||
        provider.key_pairs.detect { |kp| kp.id == merged_options_hash[:guest_access_key_pair].to_i }
    end
    unless key_pair.blank?
      merged_options_hash[:guest_access_key_pair] = key_pair.id
      merged_options_hash[:guest_access_key_pair_name] = key_pair.name
      log(:info, "Build: #{build} guest_access_key_pair_name: #{merged_options_hash[:guest_access_key_pair_name]} " \
          "guest_access_key_pair: #{merged_options_hash[:guest_access_key_pair]}")
    end

    # get the security_group from the cloud_tenant
    if merged_options_hash[:security_groups].blank?
      security_group = @tenant.security_groups.detect { |sg| object_eligible?(sg) } rescue nil
    else
      security_group = @tenant.security_groups.detect { |sg| object_eligible?(sg) && sg.name == merged_options_hash[:security_groups] } ||
        @tenant.security_groups.detect { |sg| object_eligible?(sg) && sg.id == merged_options_hash[:security_groups].to_i }
    end
    unless security_group.blank?
      merged_options_hash[:security_groups] = security_group.id
      merged_options_hash[:security_groups_id] = security_group.id
      log(:info, "Build: #{build} security_groups: #{merged_options_hash[:security_groups]}")
    end

    # get the cloud_network from the cloud_tenant
    if merged_options_hash[:cloud_network].blank?
      cloud_network = @tenant.cloud_networks.first if @tenant
    else
      if @tenant
        cloud_network = @tenant.cloud_networks.detect { |cn| cn.name == merged_options_hash[:cloud_network] } ||
          @tenant.cloud_networks.detect { |cn| cn.id == merged_options_hash[:cloud_network].to_i }
      end
    end
    unless cloud_network.blank?
      merged_options_hash[:cloud_network] = cloud_network.id
      merged_options_hash[:cloud_network_id] = cloud_network.id
      log(:info, "Build: #{build} cloud_network: #{merged_options_hash[:cloud_network]} ")
    end
    log(:info, "Processing get_network...Complete", true)
  end
end

def map_cloud_flavors(flavor)
  flavor_name = flavor.name
  if flavor.cpu_cores.to_i.zero?
    number_of_sockets = 1
  else
    number_of_sockets = flavor.cpu_cores.to_i
  end
  cores_per_socket = flavor.cpus
  vm_memory = flavor.memory / 1024**2
  log(:info, "map_cloud_flavors: #{flavor_name}, #{number_of_sockets}, #{cores_per_socket}, #{vm_memory}")
  return flavor_name, number_of_sockets, cores_per_socket, vm_memory
end

def get_flavor(build, merged_options_hash, merged_tags_hash)
  log(:info, "Processing get_flavor...", true)
  flavor_search_criteria = merged_options_hash[:flavor] || merged_options_hash[:instance_type]
  return if flavor_search_criteria.blank?
  provider = @template.ext_management_system
  log(:info, "flavor_search_criteria: #{flavor_search_criteria}")

  case @template.vendor.downcase
  when 'openstack', 'amazon';
    cloud_flavor = provider.flavors.detect {|fl| object_eligible?(fl) && fl.id == flavor_search_criteria.to_i } ||
      provider.flavors.detect { |fl| object_eligible?(fl) && fl.name.downcase.match(flavor_search_criteria) }
    log(:info, "cloud_flavor: #{cloud_flavor}") if cloud_flavor
  else
    # Manually map compute flavors for VMware, RHEV and SCVMM
    case flavor_search_criteria.gsub(/^\d*_/, '').match(/\w*$/)[0]
    when 'xsmall';  flavor_name, number_of_sockets, cores_per_socket, vm_memory = 'xsmall', 1, 1, 1024
    when 'small';   flavor_name, number_of_sockets, cores_per_socket, vm_memory = 'small', 1, 1, 2048
    when 'medium';  flavor_name, number_of_sockets, cores_per_socket, vm_memory = 'medium', 1, 2, 4096
    when 'large';   flavor_name, number_of_sockets, cores_per_socket, vm_memory = 'large', 1, 4, 8192
    when 'xlarge';  flavor_name, number_of_sockets, cores_per_socket, vm_memory = 'xlarge', 1, 8, 16384
    else
      # default to small
      flavor_name, number_of_sockets, cores_per_socket, vm_memory = 'small', 1, 1, 2048
    end
  end
  if cloud_flavor
    flavor_name, number_of_sockets, cores_per_socket, vm_memory = map_cloud_flavors(cloud_flavor)
    merged_options_hash[:instance_type] = cloud_flavor.id
  end
  if flavor_name
    merged_tags_hash[:flavor]               = flavor_name
    merged_options_hash[:number_of_sockets] = number_of_sockets
    merged_options_hash[:cores_per_socket]  = cores_per_socket
    merged_options_hash[:vm_memory]         = vm_memory
    log(:info, "Build: #{build} flavor: #{flavor_name} number_of_sockets: #{number_of_sockets} " \
        "cores_per_socket: #{cores_per_socket} vm_memory: #{vm_memory}")
  end
  log(:info, "Processing get_flavor...Complete", true)
end

# use this to set retirement
def get_retirement(build, merged_options_hash, merged_tags_hash)
  log(:info, "Processing get_retirement...", true)
  case merged_tags_hash[:environment]
  when 'dev';       merged_options_hash[:retirement], merged_options_hash[:retirement_warn] = 1.week.to_i, 3.days.to_i
  when 'test';      merged_options_hash[:retirement], merged_options_hash[:retirement_warn] = 2.days.to_i, 1.days.to_i
  when 'prod';      merged_options_hash[:retirement], merged_options_hash[:retirement_warn] = 1.month.to_i, 1.days.to_i
  else
    # Set a default retirement here
    merged_options_hash[:retirement], merged_options_hash[:retirement_warn] = 1.month.to_i, 1.week.to_i
  end
  log(:info, "Build: #{build} - retirement: #{merged_options_hash[:retirement]}" \
      " retirement_warn: #{merged_options_hash[:retirement_warn]}")
  log(:info, "Processing get_retirement...Complete", true)
end

def get_extra_options(build, merged_options_hash, merged_tags_hash)
  log(:info, "Processing get_extra_options...", true)
  # stuff the service guid & id so that the VMs can be added to the service later (see AddVMToService)
  merged_options_hash[:service_id] = @service.id unless @service.nil?
  merged_options_hash[:service_guid] = @service.guid unless @service.nil?
  log(:info, "Build: #{build} - service_id: #{merged_options_hash[:service_id]} " \
      "service_guid: #{merged_options_hash[:service_guid]}")
  log(:info, "Processing get_extra_options...Complete", true)
end

def process_builds(dialog_options_hash, dialog_tags_hash)
  builds = get_array_of_builds(dialog_options_hash)
  log(:info, "builds: #{builds.inspect}")
  builds.each do |build|
    merged_options_hash, merged_tags_hash = merge_dialog_information(build, dialog_options_hash, dialog_tags_hash)

    # get requester (figure out who the requester/user is)
    get_requester(build, merged_options_hash, merged_tags_hash)

    # now that we have the requester get the users' rbac tag filters
    @rbac_array = get_current_group_rbac_array

    # get template (search for an available template)
    get_template(build, merged_options_hash, merged_tags_hash)

    # get the cloud tenant (currently for openstack only)
    get_cloud_tenant(build, merged_options_hash, merged_tags_hash)

    # get the provision type (for vmware, rhev, msscvmm only)
    get_provision_type(build, merged_options_hash, merged_tags_hash)

    # get vm_name (either generate a vm name or use defaults)
    get_vm_name(build, merged_options_hash, merged_tags_hash)

    # get vLAN, cloud_network, security group, keypair information
    get_network(build, merged_options_hash, merged_tags_hash)

    # get cpu and memory (set the flavor)
    get_flavor(build, merged_options_hash, merged_tags_hash)

    # get retirement (set default retirement for workloads)
    get_retirement(build, merged_options_hash, merged_tags_hash)

    # get extra options ( use this section to override any options/tags that you want)
    get_extra_options(build, merged_options_hash, merged_tags_hash)

    # tag service with all rbac filter tags (for roles with vm access restrictions set to none)
    @rbac_array.each {|rbac_hash| tag_service(rbac_hash) }

    # add all rbac filter tags to merged_tags_hash (again ensure that the miq_provision has all of our tags)
    @rbac_array.each do |rbac_hash|
      rbac_hash.each do |rbac_category, rbac_tag|
        Array.wrap(rbac_tag).each do |rbac_tag_entry|
          log(:info, "Assigning Tag: {#{rbac_category}=>#{rbac_tag_entry}} to build: #{build}")
          merged_tags_hash[rbac_category.to_sym] = rbac_tag_entry
        end
      end
    end

    # create all specified categories/tags again just to be sure we got them all
    merged_tags_hash.each do |key, value|
      log(:info, "Processing tag: #{key.inspect} value: #{value.inspect}")
      tag_category = key.downcase
      Array.wrap(value).each do |tag_entry|
        process_tag(tag_category, tag_entry.downcase)
      end
    end

    # log each build's tags and options
    log(:info, "Build: #{build} - merged_tags_hash: #{merged_tags_hash.inspect}")
    log(:info, "Build: #{build} - merged_options_hash: #{merged_options_hash.inspect}")

    # call build_provision_request using merged_options_hash and merged_tags_hash to send
    # the payload to miq_request and miq_provision
    request = build_provision_request(build, merged_options_hash, merged_tags_hash)
    log(:info, "Build: #{build} - VM Provision request #{request.id} for " \
        "#{merged_options_hash[:vm_name]} successfully submitted", true)
  end
end

def set_valid_provisioning_args
  # set provisioning dialog fields everything not listed below will get stuffed into :ws_values
  valid_templateFields    = [:name, :request_type, :guid, :cluster]

  valid_vmFields          = [:vm_name, :number_of_vms, :vm_description, :vm_prefix]
  valid_vmFields         += [:number_of_sockets, :cores_per_socket, :vm_memory, :mac_address]
  valid_vmFields         += [:root_password, :provision_type, :linux_host_name, :vlan, :customization_template_id]
  valid_vmFields         += [:retirement, :retirement_warn, :placement_auto, :vm_auto_start]
  valid_vmFields         += [:linked_clone, :network_adapters, :placement_cluster_name, :request_notes]
  valid_vmFields         += [:monitoring, :floating_ip_address, :placement_availability_zone, :guest_access_key_pair]
  valid_vmFields         += [:security_groups, :cloud_tenant, :cloud_network, :cloud_subnet, :instance_type]

  valid_requester_args    = [:user_name, :owner_first_name, :owner_last_name, :owner_email, :auto_approve]
  return valid_templateFields, valid_vmFields, valid_requester_args
end

def build_provision_request(build, merged_options_hash, merged_tags_hash)
  log(:info, "Processing build_provision_request...", true)
  valid_templateFields, valid_vmFields, valid_requester_args = set_valid_provisioning_args

  # arg1 = version
  args = ['1.1']

  # arg2 = templateFields
  template_args = {}
  merged_options_hash.each { |k, v| template_args[k.to_s] = v.to_s if valid_templateFields.include?(k) }
  valid_templateFields.each { |k| merged_options_hash.delete(k) }
  args << template_args

  # arg3 = vmFields
  vm_args = {}
  merged_options_hash.each { |k, v| vm_args[k.to_s] = v.to_s if valid_vmFields.include?(k) }
  valid_vmFields.each { |k| merged_options_hash.delete(k) }
  args << vm_args

  # arg4 = requester
  requester_args = {}
  merged_options_hash.each { |k, v| requester_args[k.to_s] = v.to_s if valid_requester_args.include?(k) }
  valid_requester_args.each { |k| merged_options_hash.delete(k) }
  args << requester_args

  # arg5 = tags
  tag_args = {}
  merged_tags_hash.each { |k, v| tag_args[k.to_s] = v.to_s }
  args << tag_args

  # arg6 = Aditional Values (ws_values)
  # put all remaining merged_options_hash and merged_tags_hash in ws_values hash for later use in the state machine
  ws_args = {}
  merged_options_hash.each { |k, v| ws_args[k.to_s] = v.to_s }
  args << ws_args.merge(tag_args)

  # arg7 = emsCustomAttributes
  args << nil

  # arg8 = miqCustomAttributes
  args << nil

  log(:info, "Build: #{build} - Building provision request with the following arguments: #{args.inspect}")
  request = $evm.execute('create_provision_request', *args)

  # Reset the global variables for the next build
  @template, @user, @rbac_array = nil, nil, nil
  log(:info, "Processing build_provision_request...Complete", true)
  return request
end

begin
  $evm.root.attributes.sort.each { |k, v| log(:info, "\t Attribute: #{k} = #{v}")}

  case $evm.root['vmdb_object_type']

  when 'service_template_provision_task'
    # Executed via generic service catalog item
    @task = $evm.root['service_template_provision_task']
    @service = @task.destination
    log(:info, "Service: #{@service.name} id: #{@service.id} tasks: #{@task.miq_request_tasks.count}")

    dialog_options_hash, dialog_tags_hash = parsed_dialog_information

    # :dialog_service_name
    override_service_attribute(dialog_options_hash.fetch(0, {}), "name")
    # :dialog_service_description
    override_service_attribute(dialog_options_hash.fetch(0, {}), "description")
    # :dialog_service_retires_on
    override_service_attribute(dialog_options_hash.fetch(0, {}), "retires_on")
    # :dialog_service_retirement_warn
    override_service_attribute(dialog_options_hash.fetch(0, {}), "retirement_warn")
    # tag service with all dialog_tag_0_ parameters
    tag_service(dialog_tags_hash.fetch(0, {}))

  when 'service'
    # Executed via button from a service to provision a new VM into a Service
    @service = $evm.root['service']

  when 'vm'
    # Executed via a button, policy or an Alert on a Flexed VM
    vm = $evm.root['vm']

    @service = vm.service rescue nil
    # determine what type of object to keep track of the tags
    if @service.blank?
      tag_object = vm
    else
      # tag_object = @service
      tag_object = vm
      tag_object_type = 'vm'
    end

    # Get miq_provision from vm
    prov = vm.miq_provision
    raise "miq_provision object not found." if prov.nil?

    # log the tags from the tag_object
    log(:info, "tag_object: #{tag_object.name} tags: #{tag_object.tags.inspect}")

    # Get the tag_object flex_monitor tag
    flex_monitor = tag_object.tags(:flex_monitor).first rescue false
    # Skip processing if tag_object is not tagged with flex_monitor = true
    raise  "tag_object: #{tag_object} tag: {:flex_monitor => #{flex_monitor}}" unless flex_monitor =~ (/(true|t|yes|y|1)$/i)

    # Get the flex_maximum tag else set it to zero
    flex_maximum = tag_object.tags(:flex_maximum).first.to_i
    # Get the flex_current tag else set it to zero
    flex_current = tag_object.tags(:flex_current).first.to_i
    # Get the flex_pending tag else set it to zero
    flex_pending = tag_object.tags(:flex_pending).first.to_i

    flex_options_hash = {}
    if $evm.root['object_name'] == 'Event'
      # object_name = 'Event' means that we were triggered from an Alert
      log(:info, "Detected Alert driven event - $evm.root['miq_alert_description']: #{$evm.root['miq_alert_description'].inspect}")
      flex_options_hash[:flex_reason] = $evm.root['miq_alert_description']
    elsif $evm.root['ems_event']
      # ems_event means that were triggered via Control Policy
      log(:info, "Detected Policy driven event - $evm.root['ems_event']: #{$evm.root['ems_event'].inspect}")
      flex_options_hash[:flex_reason] = $evm.root['ems_event'].event_type
    else
      unless $evm.root['dialog_miq_alert_description'].nil?
        log(:info, "Detected Service dialog driven event")
        # If manual creation add dialog input notes to flex_options_hash
        flex_options_hash[:flex_reason] = "VM flexed manually - #{$evm.root['dialog_miq_alert_description']}"
      else
        log(:info, "Detected manual driven event")
        # If manual creation add default notes to flex_options_hash
        flex_options_hash[:flex_reason] = "VM flexed manually"
      end
    end

    # Create flex_pending tags if they do not already exist
    process_tags('flex_pending', true, flex_pending)

    # if flex_current + flex_pending is less than flex_maximum
    if flex_current + flex_pending < flex_maximum
      # Increment flex_pending by 1
      new_flex_pending = flex_pending + 1
      # Create flex_pending tags if they do not already exist
      process_tags('flex_pending', true, new_flex_pending)

      valid_templateFields, valid_vmFields, valid_requester_args = set_valid_provisioning_args

      # Inherit all of the VMs provisioning templateFields
      valid_templateFields.each { |key| flex_options_hash[key] = prov.get_option(key)}
      # Inherit all of the VMs provisioning vmFields
      valid_vmFields.each { |key| flex_options_hash[key] = prov.get_option(key) unless prov.get_option(key).blank?}
      # Inherit all of the VMs provisioning requester information
      valid_requester_args.each { |key| flex_options_hash[key] = prov.get_option(key)}

      flex_tags_hash = {}
      # Inherit all of the source VM tags
      tag_object.tags.each do |cat_tagname|
        category, tag_value = cat_tagname.split('/')
        next if category.include?('flex') || category.include?('folder_path')
        log(:info, "Adding category: {#{category} => #{tag_value}} to flex_tags_hash")
        flex_tags_hash["#{category}"] = tag_value
      end

      # Override provisioning options here
      flex_options_hash[:service_id]        = @service.id
      flex_options_hash[:number_of_vms]     = 1
      flex_options_hash[:user_name]         = prov.userid
      flex_options_hash[:requester_id]      = prov.requester_id
      flex_options_hash[:user_id]           = vm.evm_owner_id
      flex_options_hash[:flex_vm_guid]      = vm.guid
      flex_options_hash[:flex_vm_name]      = vm.name
      flex_options_hash[:guid]              = prov.vm_template.guid
      flex_options_hash[:name]              = prov.vm_template.name

      # Tag service with :flex_pending => new_flex_pending
      unless tag_object.tagged_with?('flex_pending', new_flex_pending)
        log(:info, "Assigning tag: {:flex_pending => #{new_flex_pending}} to tag_object: #{tag_object.name}")
        tag_object.tag_assign("flex_pending/#{new_flex_pending}")
      end

      # Convert flex_tags_hash keys to symbols
      (dialogs_tags_hash||={})[1] = Hash[flex_tags_hash.map{ |k, v| [k.to_sym, v] }]
      log(:info, "Inspecting dialogs_tags_hash: #{dialogs_tags_hash.inspect}")
      # Convert flex_options_hash keys to symbols
      (dialogs_options_hash||={})[1] = Hash[flex_options_hash.map{ |k, v| [k.to_sym, v] }]
      log(:info, "Inspecting dialogs_options_hash: #{dialogs_options_hash.inspect}")
    else
      raise "tag_object: #{tag_object.name} flex_maximum: #{flex_maximum} has been reached"
    end
  else
    raise "Invalid $evm.root['vmdb_object_type']: #{$evm.root['vmdb_object_type']}"
  end # case $evm.root['vmdb_object_type']

  # prepare the builds and execute them
  process_builds(dialog_options_hash, dialog_tags_hash)

rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  @task.finished("#{err}") if @task
  @service.remove_from_vmdb if @service
  exit MIQ_ABORT
end

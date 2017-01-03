=begin
 rds_create_instance.rb

 Author: David Costakos <dcostako@redhat.com>, Kevin Morey <kevin@redhat.com>

 Description: This method creates an RDS instance in AWS
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

def create_tags(category, single_value, tag)
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

def process_tag(tag_category, tag_value)
  return if tag_value.blank?
  create_tags(tag_category, true, tag_value)
end

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

def override_service_attribute(dialogs_options_hash, attr_name)
  service_attr_name = "service_#{attr_name}".to_sym
  log(:info, "Processing override_attribute for #{service_attr_name}...", true)
  attr_value = dialogs_options_hash.fetch(service_attr_name, nil)
  if attr_name == 'retires_on'
    attr_value = (DateTime.now+attr_value.to_i).strftime("%Y-%m-%d") unless attr_value.to_i.zero?
  end
  attr_value = "#{@service.name}-#{Time.now.strftime('%Y%m%d-%H%M%S')}" if attr_name == 'name' && attr_value.nil?
  log(:info, "Setting service attribute: #{attr_name} to: #{attr_value}")
  @service.send("#{attr_name}=", attr_value)
  log(:info, "Processing override_attribute for #{service_attr_name}...Complete", true)
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

def get_aws_client(type='RDS', constructor='Client', body_hash={})
  require 'aws-sdk'

  username = @provider.authentication_userid
  password = @provider.authentication_password
  Aws.config[:credentials] = Aws::Credentials.new(username, password)
  Aws.config[:region]      = @provider.provider_region
  return Aws::const_get("#{type}")::const_get("#{constructor}").new(body_hash)
end

def yaml_data(option)
  @task.get_option(option).nil? ? nil : YAML.load(@task.get_option(option))
end

def parsed_dialog_information
  dialog_options_hash = yaml_data(:parsed_dialog_options)
  dialog_tags_hash = yaml_data(:parsed_dialog_tags)
  raise if dialog_options_hash.blank? && dialog_tags_hash.blank?
  log(:info, "dialog_options_hash: #{dialog_options_hash.inspect}")
  log(:info, "dialog_tags_hash: #{dialog_tags_hash.inspect}")
  return dialog_options_hash, dialog_tags_hash
end

def get_retirement(merged_options_hash, merged_tags_hash)
  log(:info, "Processing get_retirement...", true)
  case merged_tags_hash[:environment]
  when 'dev';       merged_options_hash[:retirement], merged_options_hash[:retirement_warn] = 1.week.to_i, 3.days.to_i
  when 'test';      merged_options_hash[:retirement], merged_options_hash[:retirement_warn] = 2.days.to_i, 1.days.to_i
  when 'prod';      merged_options_hash[:retirement], merged_options_hash[:retirement_warn] = 1.month.to_i, 1.days.to_i
  else
    # Set a default retirement here
    merged_options_hash[:retirement], merged_options_hash[:retirement_warn] = 1.month.to_i, 1.week.to_i
  end
  log(:info, "retirement: #{merged_options_hash[:retirement]}" \
                         " retirement_warn: #{merged_options_hash[:retirement_warn]}")
  log(:info, "Processing get_retirement...Complete", true)
end

def decrypt_passwd(password)
  $LOAD_PATH.unshift File.expand_path('/var/www/miq/vmdb/gems/pending/util/', __FILE__)
  $LOAD_PATH.unshift File.expand_path('/var/www/miq/vmdb/gems/pending/', __FILE__)
  require 'miq-password.rb'
  MiqPassword.key_root = "/var/www/miq/vmdb/certs"
  return MiqPassword.decrypt(password)
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
  when 'service_template_provision_task'
    @task = $evm.root['service_template_provision_task']
    log(:info, "Task: #{@task.id} Request: #{@task.miq_request.id} Type:#{@task.type}")
    @service = @task.destination
    log(:info,"Service: #{@service.name} Id: #{@service.id}")
    @provider = get_provider
  else
    exit MIQ_OK
  end

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

  options_hash = dialog_options_hash.fetch(0, {})

  valid_rds_options_strings  = [:db_instance_identifier, :engine, :db_instance_class, :allocated_storage, :master_username]
  valid_rds_options_integers  = [:allocated_storage, :engine_version]
  valid_rds_options_passwords  = [:master_user_password]

  rds_options_hash = {}
  options_hash.each { |k, v| rds_options_hash[k] = v.to_s if valid_rds_options_strings.include?(k) }
  options_hash.each { |k, v| rds_options_hash[k] = v.to_i if valid_rds_options_integers.include?(k) }
  options_hash.each { |k, v| rds_options_hash[k] = decrypt_passwd(v) if valid_rds_options_passwords.include?(k) }

  log(:info, "rds_options_hash: #{rds_options_hash}")

  rds = get_aws_client
  log(:info, "RDS Client: #{rds}")

  rds_create_instance_hash = rds.create_db_instance(rds_options_hash).to_h
  log(:info, "RDS Instance Created: #{rds_create_instance_hash.inspect}")
  log(:info, "RDS Instance Created: #{rds_create_instance_hash[:db_instance_identifier]}", true)

  set_service_custom_variables(rds_create_instance_hash)

  @service.custom_set(:provider_id, "#{@provider.id}")

  # Make sure these options are available so they can be used for notification later
  @task.set_option(:engine_version, rds_create_instance_hash[:engine_version])
  @task.set_option(:engine, rds_create_instance_hash[:engine])
  @task.set_option(:db_instance_identifier , rds_create_instance_hash[:db_instance_identifier])

rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  @task.finished("#{err}") if @task
  @service.remove_from_vmdb if @service
  exit MIQ_ABORT
end

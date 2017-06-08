=begin
  generic_service_initialization.rb

  Author: Kevin Morey <kevin@redhat.com>

  Description: Allows for customizing 'Ansible Inside' services

   This method Performs the following functions:
    1. YAML load the Service Dialog Options from @task.get_option(:parsed_dialog_options)
    2. Set the name and description of the service
    3. Set tags on the service
    4. Set retirement on the service

  Inputs: dialog_service_name, dialog_service_description, dialog_tag_0_<category>, 
    dialog_service_retires_on, dialog_service_retirement_warn

  Example: {:dialog_service_name=>"test2", :dialog_service_description=>"test2", 
    :dialog_service_retires_on=>"7", :dialog_service_retirement_warn=>"1"}

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
def log_and_update_message(level, msg, update_message = false)
  $evm.log(level, msg.to_s)
  @task.message = msg if @task && (update_message || level == 'error')
end

# Loop through all tags from the dialog and create the categories and tags automatically
def create_tags(category, single_value, tag)
  # Convert to lower case and replace all non-word characters with underscores
  category_name = category.to_s.downcase.gsub(/\W/, '_')
  tag_name = tag.to_s.downcase.gsub(/\W/, '_')
  # if the category exists else create it
  unless $evm.execute('category_exists?', category_name)
    log_and_update_message(:info, "Creating Category: {#{category_name} => #{category}}")
    $evm.execute('category_create', :name         => category_name,
                 :single_value => single_value,
                 :description  => category.to_s)
  end
  # if the tag exists else create it
  return if $evm.execute('tag_exists?', category_name, tag_name)
  log_and_update_message(:info, "Creating tag: {#{tag_name} => #{tag}}")
  $evm.execute('tag_create', category_name, :name => tag_name, :description => tag.to_s)
end

def create_category_and_tags_if_necessary(dialog_tags_hash)
  dialog_tags_hash.each do |category, tag|
    Array.wrap(tag).each do |tag_entry|
      create_tags(category, true, tag_entry)
    end
  end
end

def override_service_name(dialog_options_hash)
  log_and_update_message(:info, "Processing override_service_name...", true)
  new_service_name = dialog_options_hash.fetch(:service_name, nil)
  new_service_name = "#{@service.name}-#{Time.now.strftime('%Y%m%d-%H%M%S')}" if new_service_name.blank?

  log_and_update_message(:info, "Service name: #{new_service_name}")
  @service.name = new_service_name
  log_and_update_message(:info, "Processing override_service_name...Complete", true)
end

def override_service_description(dialog_options_hash)
  log_and_update_message(:info, "Processing override_service_description...", true)
  new_service_description = dialog_options_hash.fetch(:service_description, nil)
  return if new_service_description.blank?

  log_and_update_message(:info, "Service description #{new_service_description}")
  @service.description = new_service_description
  log_and_update_message(:info, "Processing override_service_description...Complete", true)
end

def override_service_retirement(dialog_options_hash, dialog_tags_hash)
  log_and_update_message(:info, "Processing override_service_retirement...", true)
  new_service_retires_on = dialog_options_hash.fetch(:service_retires_on, nil).to_i
  return if new_service_retires_on.zero?

  todays_date = Date.parse(DateTime.now().strftime("%F"))
  @service.retires_on = todays_date + new_service_retires_on
  log_and_update_message(:info, "Service retires_on #{@service.retires_on}")
  new_service_retirement_warn = dialog_options_hash.fetch(:service_retirement_warn, nil).to_i
  @service.retirement_warn = new_service_retirement_warn
  log_and_update_message(:info, "Service retirement_warn #{@service.retirement_warn}")

  log_and_update_message(:info, "Processing override_service_retirement...Complete", true)
end

def tag_service(dialog_tags_hash)
  return if dialog_tags_hash.nil?

  log_and_update_message(:info, "Processing tag service...", true)

  dialog_tags_hash.each do |key, value|
    log_and_update_message(:info, "Processing Tag Key: #{key.inspect}  value: #{value.inspect}")
    next if value.blank?
    get_service_tags(key.downcase, value)
  end
  log_and_update_message(:info, "Processing tag_service...Complete", true)
end

def get_service_tags(tag_category, tag_value)
  Array.wrap(tag_value).each do |tag_entry|
    assign_service_tag(tag_category, tag_entry)
  end
end

def assign_service_tag(tag_category, tag_value)
  $evm.log(:info, "Adding tag category: #{tag_category} tag: #{tag_value} to Service: #{@service.name}")
  @service.tag_assign("#{tag_category}/#{tag_value}")
end

def service_item_dialog_values(dialogs_options_hash)
  merged_options_hash = Hash.new { |h, k| h[k] = {} }
  provision_index = determine_provision_index

  if dialogs_options_hash[0].nil?
    merged_options_hash = dialogs_options_hash[provision_index] || {}
  else
    merged_options_hash = dialogs_options_hash[0].merge(dialogs_options_hash[provision_index] || {})
  end
  merged_options_hash
end

def service_item_tag_values(dialogs_tags_hash)
  merged_tags_hash         = Hash.new { |h, k| h[k] = {} }
  provision_index = determine_provision_index

  # merge dialog_tag_0 stuff with current build
  if dialogs_tags_hash[0].nil?
    merged_tags_hash = dialogs_tags_hash[provision_index] || {}
  else
    merged_tags_hash = dialogs_tags_hash[0].merge(dialogs_tags_hash[provision_index] || {})
  end
  merged_tags_hash
end

def determine_provision_index
  service_resource = @task.service_resource
  if service_resource
    # Increment the provision_index number since the child resource starts with a zero
    provision_index = service_resource.provision_index ? service_resource.provision_index + 1 : 0
    log_and_update_message(:info, "Bundle --> Service name: #{@service.name}> provision_index: #{provision_index}")
  else
    provision_index = 1
    log_and_update_message(:info, "Item --> Service name: #{@service.name}> provision_index: #{provision_index}")
  end
  provision_index
end

def remove_service
  log_and_update_message(:info, "Processing remove_service...", true)
  if @service
    log_and_update_message(:info, "Removing Service: #{@service.name} id: #{@service.id} due to failure")
    @service.remove_from_vmdb
  end
  log_and_update_message(:info, "Processing remove_service...Complete", true)
end

def merge_dialog_information(dialog_options_hash, dialog_tags_hash)
  merged_options_hash = service_item_dialog_values(dialog_options_hash)
  merged_tags_hash = service_item_tag_values(dialog_tags_hash)

  log_and_update_message(:info, "merged_options_hash: #{merged_options_hash.inspect}")
  log_and_update_message(:info, "merged_tags_hash: #{merged_tags_hash.inspect}")
  return merged_options_hash, merged_tags_hash
end

def yaml_data(option)
  @task.get_option(option).nil? ? nil : YAML.load(@task.get_option(option))
end

def parsed_dialog_information
  dialog_options_hash = yaml_data(:parsed_dialog_options)
  dialog_tags_hash = yaml_data(:parsed_dialog_tags)
  if dialog_options_hash.blank? && dialog_tags_hash.blank?
    log_and_update_message(:info, "Instantiating dialog_parser to populate dialog options")
    $evm.instantiate('/Service/Provisioning/StateMachines/Methods/DialogParser')
    dialog_options_hash = yaml_data(:parsed_dialog_options)
    dialog_tags_hash = yaml_data(:parsed_dialog_tags)
  end

  merged_options_hash, merged_tags_hash = merge_dialog_information(dialog_options_hash, dialog_tags_hash)
  return merged_options_hash, merged_tags_hash
end

begin

  @task = $evm.root['service_template_provision_task']

  @service = @task.destination
  log_and_update_message(:info, "Service: #{@service.name} Id: #{@service.id} Tasks: #{@task.miq_request_tasks.count}")

  dialog_options_hash, dialog_tags_hash = parsed_dialog_information

  unless dialog_options_hash.blank?
    override_service_name(dialog_options_hash)
    override_service_description(dialog_options_hash)
    override_service_retirement(dialog_options_hash, dialog_tags_hash)
  end

  unless dialog_tags_hash.blank?
    create_category_and_tags_if_necessary(dialog_tags_hash)
    tag_service(dialog_tags_hash)
  end

rescue => err
  log_and_update_message(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  @task.finished(err.to_s) if @task
  # remove_service if @service
  exit MIQ_ABORT
end

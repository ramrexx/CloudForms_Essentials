=begin
  initialize_service_variables.rb

  Author: Kevin Morey <kevin@redhat.com>

  Description: This method initializes service variables for use in the state machine
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

def merge_service_item_dialog_values(build, dialogs_hash)
  merged_hash = Hash.new { |h, k| h[k] = {} }
  if dialogs_hash[0].nil?
    merged_hash = dialogs_hash[build] || {}
  else
    merged_hash = dialogs_hash[0].merge(dialogs_hash[build] || {})
  end
  merged_hash
end

def merge_dialog_information(build, dialog_options_hash, dialog_tags_hash)
  merged_options_hash = merge_service_item_dialog_values(build, dialog_options_hash)
  merged_tags_hash = merge_service_item_dialog_values(build, dialog_tags_hash)
  log(:info, "build: #{build} merged_options_hash: #{merged_options_hash.inspect}")
  log(:info, "build: #{build} merged_tags_hash: #{merged_tags_hash.inspect}")
  return merged_options_hash, merged_tags_hash
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

  # load up only the default 0 options and tags 
  options_hash = dialog_options_hash.fetch(0, {})
  tags_hash    = dialog_tags_hash.fetch(0, {})

  # save options and tags to workspace variable to make it easier to grab later on in the state machine
  $evm.set_state_var(:options_hash, options_hash)
  log(:info, "Workspace variable updated {:options_hash=>#{$evm.get_state_var(:options_hash)}}")
  $evm.set_state_var(:tags_hash, tags_hash)
  log(:info, "Workspace variable updated {:tags_hash=>#{$evm.get_state_var(:tags_hash)}}")

rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  @task.finished("#{err}") if @task
  @service.remove_from_vmdb if @service
  exit MIQ_ABORT
end

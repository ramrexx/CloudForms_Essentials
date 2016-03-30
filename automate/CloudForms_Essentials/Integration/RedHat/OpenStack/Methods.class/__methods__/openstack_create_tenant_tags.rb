=begin
  openstack_create_tenant_tags.rb

  Author: Dave Costakos <david.costakos@redhat.com>, Kevin Morey <kevin@redhat.com>

  Description: This method creates CFME tags for each Openstack cloud_tenant
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

# process_tags - Dynamically create categories and tags
def process_tags( category, category_description, single_value, tag, tag_description=tag )
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

begin
  $evm.root.attributes.sort.each { |k, v| log(:info, "\t $evm.root Attribute - #{k}: #{v}")}

  category = $evm.root['dialog_category'] || 'tenant'
  category_description = 'Tenant'

  $evm.vmdb(:cloud_tenant).all.each do |ct|
    log(:info, "Processing cloud_tenant: #{ct.inspect}")
    ct.description.blank? ? (new_description = ct.name) : (new_description = ct.description)
    process_tags(category, category_description, false, ct.name, new_description)
  end

rescue => err
  log(:error, "#{err} [#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

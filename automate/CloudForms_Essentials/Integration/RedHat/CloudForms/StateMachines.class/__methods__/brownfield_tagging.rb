=begin
 brownfield_tagging.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method performs the following 
    a) Look up VM guest application 
    b) Look up VM guest application version
    c) Look up VM guest user account 
    d) tag VM

    This is a great use case for brown-field environments. With this method you 
    	can auto-tag VMs based on guest, applications, versions, even users
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

def process_tags(category, single_value, tag)
  # Convert to lower case and replace all non-word characters with underscores
  category_name = category.to_s.downcase.gsub(/\W/,'_')
  tag_name = tag.to_s.downcase.gsub(/\W/,'_')

  # if the category exists else create it
  unless $evm.execute('category_exists?', category_name)
    log(:info, "Category <#{category_name}> doesn't exist, creating category")
    $evm.execute('category_create', :name => category_name, :single_value => single_value, :description => "#{category}")
  end
  # if the tag exists else create it
  unless $evm.execute('tag_exists?', category_name, tag_name)
    log(:info, "Adding new tag <#{tag_name}> in Category <#{category_name}>")
    $evm.execute('tag_create', category_name, :name => tag_name, :description => "#{tag}")
  end
  return category_name, tag_name
end

begin

  @vm = $evm.root['vm']

  # get variables from dialog
  guest_application_name = $evm.root['dialog_guest_application_name'].downcase rescue nil
  guest_application_version = $evm.root['dialog_guest_application_version'].downcase rescue nil
  # guest_account = $evm.root['dialog_guest_application_account'] || 'clouduser'
  log(:info, "guest_application_name: #{guest_application_name}")
  log(:info, "guest_application_version: #{guest_application_version}")

  category = $evm.root['dialog_category'] rescue 'Application'
  tag = "#{guest_application_name} #{guest_application_version}"

  guest_application = @vm.guest_applications.detect {|ga| ga.name.downcase == guest_application_name} rescue nil

  log(:info, "guest_application: #{guest_application.inspect}")

  if guest_application
    if guest_application.version ==  guest_application_version
      #if  @vm.accounts.detect {|a| a.name==guest_account}
      category_name, tag_name = process_tags(category, true, tag)
      @vm.tag_assign("#{category_name}/#{tag_name}")
    end
  end

rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

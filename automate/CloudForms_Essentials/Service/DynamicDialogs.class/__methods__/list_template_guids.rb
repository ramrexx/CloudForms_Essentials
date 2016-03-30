=begin
 list_template_guids.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method builds a dialog of all tempalate guids based 
    on the RBAC filters applied to a users group
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

def get_user
  user_search = $evm.root['dialog_userid'] || $evm.root['dialog_evm_owner_id']
  user = $evm.vmdb('user').find_by_id(user_search) || $evm.vmdb('user').find_by_userid(user_search) ||
    $evm.root['user']
  user
end

def get_current_group_rbac_array
  rbac_array = []
  unless @user.current_group.filters.blank?
    @user.current_group.filters['managed'].flatten.each do |filter|
      next unless /(?<category>\w*)\/(?<tag>\w*)$/i =~ filter
      rbac_array << {category=>tag}
    end
  end
  log(:info, "@user: #{@user.userid} RBAC filters: #{rbac_array}")
  rbac_array
end

def object_eligible?(obj)
  return false if obj.archived || obj.orphaned
  @rbac_array.each do |rbac_hash|
    rbac_hash.each do |rbac_category, rbac_tags|
      Array.wrap(rbac_tags).each {|rbac_tag_entry| return false unless obj.tagged_with?(rbac_category, rbac_tag_entry) }
    end
    true
  end
end

begin

  @user = get_user
  @rbac_array = get_current_group_rbac_array

  dialog_hash = {}
  $evm.vmdb(:miq_template).all.each do |template|
    if object_eligible?(template)
      dialog_hash[template[:guid]] = "#{template.name} on #{template.ext_management_system.name}"
    end
  end

  if dialog_hash.blank?
    dialog_hash[''] = "< No templates found tagged with #{rbac_array} >"
  else
    $evm.object['default_value'] = dialog_hash.first[0]
  end

  $evm.object["values"] = dialog_hash
  log(:info, "$evm.object['values']: #{$evm.object['values'].inspect}")

rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

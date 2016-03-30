=begin
 quota_initialize_tags.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method creates extra quota tag categories and sample 
   tag entries during services quota. This is especially helpful for 
   managing quotas by group. I.e. quota_source
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

def create_category_and_tags_if_necessary(category_hash)
  unless $evm.execute('category_exists?', category_hash[:name])
    log(:info, "Creating Category: #{category_hash[:name]} => #{category_hash[:example_text]} with description: #{category_hash[:description]}")
    $evm.execute('category_create', category_hash)
  end

  category_hash[:tag_values].each do |tag_name, tag_description|
    next if $evm.execute('tag_exists?', category_hash[:name], tag_name.to_s)
    log(:info, "Creating tag: {#{tag_name} => #{tag_description}}")
    $evm.execute('tag_create', category_hash[:name], :name => tag_name.to_s, :description => "#{tag_description}")
  end
end

begin
  (quota_max_vms||={})[:name]       = 'quota_max_vms'
  quota_max_vms[:example_text]      = 'Quota - Max VMs'
  quota_max_vms[:description]       = 'Quota - Max VMs'
  quota_max_vms[:single_value]      = true
  quota_max_vms[:tag_values]        = [[1,1],[2,2],[3,3],[4,4],[5,5]]
  create_category_and_tags_if_necessary(quota_max_vms)

  (quota_warn_cpu||={})[:name]      = 'quota_warn_cpu'
  quota_warn_cpu[:example_text]     = 'Quota - Warn CPU'
  quota_warn_cpu[:description]      = 'Quota - Warn CPU'
  quota_warn_cpu[:single_value]     = true
  quota_warn_cpu[:tag_values]       = [[1,1],[2,2],[3,3],[4,4],[5,5]]
  create_category_and_tags_if_necessary(quota_warn_cpu)

  (quota_warn_memory||={})[:name]   = 'quota_warn_memory'
  quota_warn_memory[:example_text]  = 'Quota - Warn Memory'
  quota_warn_memory[:description]   = 'Quota - Warn Memory'
  quota_warn_memory[:single_value]  = true
  quota_warn_memory[:tag_values]    = [[1024,'1GB'],[10240,'10GB'],[20480,'20GB'],[40960,'40GB'],[51200,'50GB']]
  create_category_and_tags_if_necessary(quota_warn_memory)

  (quota_warn_vms||={})[:name]      = 'quota_warn_vms'
  quota_warn_vms[:example_text]     = 'Quota - Warn Vms'
  quota_warn_vms[:description]      = 'Quota - Warn Vms'
  quota_warn_vms[:single_value]     = true
  quota_warn_vms[:tag_values]        = [[1,1],[2,2],[3,3],[4,4],[5,5]]
  create_category_and_tags_if_necessary(quota_warn_vms)

  (quota_warn_storage||={})[:name]  = 'quota_warn_storage'
  quota_warn_storage[:example_text] = 'Quota - Warn Storage'
  quota_warn_storage[:description]  = 'Quota - Warn Storage'
  quota_warn_storage[:single_value] = true
  quota_warn_storage[:tag_values]   = [[10,'10GB'],[20,'20GB'],[50,'50GB'],[100,'100GB'],[1000,'1TB']]
  create_category_and_tags_if_necessary(quota_warn_storage)

  # Set Ruby rescue behavior
rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_STOP
end

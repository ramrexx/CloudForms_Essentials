=begin
 list_quota_usage.rb

 Author: David Costakos <dcostako@redhat.com>, Kevin Morey <kevin@redhat.com>

 Description: This method lists quota usage for current user in a dynamic text box
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

def retry_method(retry_time='1.minute', msg='RETRYING')
  log(:info, "#{msg} - retrying in #{retry_time}}", true)
  $evm.root['ae_result'] = 'retry'
  $evm.root['ae_retry_interval'] = retry_time
  exit MIQ_OK
end

begin
  $evm.root.attributes.sort.each { |k, v| log(:info, "\t $evm.root Attribute - #{k}: #{v}")}

  user = $evm.root['user']
  group = user.current_group

  memory = group.allocated_memory / 1024**3
  vcpu = group.allocated_vcpu
  storage = group.allocated_storage / 1024**3

  log(:info, "Allocated Memory: #{memory} GB")
  log(:info, "Allocated VCPUs: #{vcpu}")
  log(:info, "Allocated Storage: #{storage} GB")

  log(:info, "Group Tags: #{group.tags.inspect}")

  quota_max_memory = group.tags(:quota_max_memory).first.to_i / 1024
  quota_max_storage = group.tags(:quota_max_storage).first.to_i
  quota_max_cpu = group.tags(:quota_max_cpu).first.to_i

  quota_max_memory = "Unlimited" if quota_max_memory.zero?
  quota_max_storage = "Unlimited" if quota_max_storage.zero?
  quota_max_cpu = "Unlimited" if quota_max_cpu.zero?

  log(:info, "Quota Max Memory: #{quota_max_memory} GB")
  log(:info, "Quota Max Storage: #{quota_max_storage} GB")
  log(:info, "Quota VCPUs: #{quota_max_cpu}")

  string = "\n"
  string += "Memory: #{memory} GB of #{quota_max_memory} GB used\n"
  string += "VCPUs:  #{vcpu} of #{quota_max_cpu} used\n"
  string += "Storage: #{storage} of #{quota_max_storage} GB used\n"

  log(:info, "Info: #{string}")
  $evm.object['value'] = string

  # Ruby rescue
rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

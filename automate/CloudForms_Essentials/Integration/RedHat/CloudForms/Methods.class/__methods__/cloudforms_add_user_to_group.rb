=begin
 cloudforms_add_user_to_group.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method is used to add a user to miq_group relationship
   for the purpose of group context switching
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

def run_linux_admin(cmd, timeout=10)
  require 'linux_admin'
  require 'timeout'
  begin
    Timeout::timeout(timeout) {
      log(:info, "Executing #{cmd} with timeout of #{timeout} seconds")
      result = LinuxAdmin.run(cmd)
      log(:info, "Inspecting output: #{result.output.inspect}")
      log(:info, "Inspecting error: #{result.error.inspect}") unless result.error.blank?
      log(:info, "Inspecting exit_status: #{result.exit_status.inspect}")
      return result
    }
  rescue => timeout
    log(:error, "Error in execution: #{timeout.class} #{timeout} #{timeout.backtrace.join("\n")}")
    return false
  end
end

begin
  $evm.root.attributes.sort.each { |k, v| log(:info, "\t $evm.root Attribute - #{k}: #{v}")}

  group_id = $evm.root['dialog_group_id'].to_i
  user_id = $evm.root['dialog_user_id'] || $evm.root['user'].id

  unless group_id.zero?
    servername = $evm.object['servername']
    username = $evm.object['username']
    password = $evm.object.decrypt('password')
    database_name = 'vmdb_production'

    cmd  = "export PGPASSWORD=#{password};"
    cmd += "psql -U #{username} -h #{servername} -d #{database_name} -c 'INSERT INTO miq_groups_users(miq_group_id, user_id) VALUES (#{group_id}, #{user_id});';"
    cmd += "unset PGPASSWORD"

    result = run_linux_admin(cmd, 300)
    if result
      log(:info, "Successfully added relationship for user_id #{user_id} to group_id: #{group_id}")
    else
      raise "Failed to added relationship for user_id #{user_id} to group_id: #{group_id}"
    end
  end

rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

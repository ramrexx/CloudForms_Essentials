=begin
 rhev_enter_maintenance_mode_check.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method checks to ensure that the host is in maintenance mode
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
  # Get host from root object
  @host = $evm.root['host']

  log(:info, "Host: #{@host.name} has Power State: #{@host.power_state}")

  # retry method unless is in maintenance mode
  unless host.power_state == "maintenance"
    retry_method()
  end


  # Set Ruby rescue behavior
rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

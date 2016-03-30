=begin
 rhev_email_status.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method emails the user regarding the RHEV hosts power state
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

begin
  @host = $evm.root['host']

  # Override the default appliance IP Address below
  appliance = nil || $evm.root['miq_server'].ipaddress || $evm.root['miq_server'].hostname rescue nil

  # Get requester object
  @user = $evm.root['user']

  # get users email address else get it from the model
  @user.email.nil? ? (to = nil || $evm.root['to_email_address']) : (to = @user.email)

  # Get from_email_address from model unless specified below
  from = nil || $evm.object['from_email_address']

  # Get signature from model unless specified below
  signature = nil || $evm.object['signature']

  # Set email subject
  subject = "Host: #{@host.name} - has a power_state: #{@host.power_state}"

  # Build email body
  body = "Hello, "
  body += "<br><br>Host Information:"
  body += "User: #{@user.userid}"
  body += "Hostname: #{@host.hostname}"
  body += "IP Address: #{@host.ipaddress}"
  body += "Provider: #{@host.ext_management_system.name}"
  body += "Cluster: #{@host.ems_cluster.name}"
  body += "Number of VMs:: #{@host.vms.count}"
  body += "For more additional information: <a href='https://#{appliance}/host/show/#{@host.id}'</a>"
  body += "<br><br> Thank you,"
  body += "<br> #{signature}"

  # Send email to requester
  log(:info, "Sending email to <#{to}> from <#{from}> subject: <#{subject}>")
  $evm.execute(:send_email, to, from, subject, body)

rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_STOP
end

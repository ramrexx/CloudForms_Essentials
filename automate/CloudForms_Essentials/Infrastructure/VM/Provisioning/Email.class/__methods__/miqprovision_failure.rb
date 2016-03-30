=begin
  miqprovision_failure.rb

  Author: Kevin Morey <kevin@redhat.com>

  Description: This method sends an email when an miq_provision task fails
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

def send_mail(to, from, subject, body)
  log(:info, "Sending email to #{to} from #{from} subject: #{subject}")
  $evm.execute(:send_email, to, from, subject, body)
end

def from_email_address
  $evm.object['from_email_address']
end

def signature
  $evm.object['signature']
end

def appliance
  $evm.root['miq_server'].ipaddress
end

def ref_url
  "<a href='https://#{appliance}/miq_request/show/#{@miq_request.id}'>https://#{appliance}/miq_request/show/#{@miq_request.id}</a>"
end

def error_message
  @task.message
end

def requester
  @miq_request.requester
end

def service
  service_search = @task.get_option(:service_guid) || @ws_values[:service_id]
  service = $evm.vmdb(:service).find_by_guid(service_search) || $evm.vmdb(:service).find_by_id(service_search)
  service
end

def footer
  body = "<br><br>For more information you can go to: <br>"
  body += ref_url
  body += "<br><br> Thank you,"
  body += "<br> #{signature}"
  body
end

def requester_email_address
  owner_email = @task.options.fetch(:owner_email, nil)
  email = owner_email || requester.email || $evm.object['to_email_address']
  log(:info, "Requester email: #{email}")
  email
end

def requester_text
  body = "Hello, "
  body += "Your provision job failed for the following reason: <b>#{error_message}</b><br>"
  body += "Please contact an administrator for assistance.<br><br>"
  body += "Provision Quick Summary:<br>"
  body += "Request id: #{@miq_request.id}<br>"
  body += "Provision id: #{@task.id}<br>"
  body += "Provision description: #{@miq_request.description}<br>"
  body += "Service: #{service.name}<br>" if service
  body += footer
  body
end

def requester_email
  log(:info, "Requester email logic starting")
  to_email_address = requester_email_address + ',' + administrator_email_address
  subject = "Task #{@task.id} - Your provision task has failed"
  send_mail(to_email_address, from_email_address, subject, requester_text)
end


def administrator_email_address
  admin_email = @task.get_option(:admin_email) || @ws_values[:admin_email]
  email = admin_email || $evm.object['to_email_address']
  log(:info, "Administrator email: #{email}")
  email
end

def administrator_text
  body = "Hello, "
  body += "Provision job failed for the following reason: <b>#{error_message}</b><br><br>"
  body += "Provision Quick Summary:<br>"
  body += "Request id: #{@miq_request.id}<br>"
  body += "Provision id: #{@task.id}<br>"
  body += "Provision description: #{@miq_request.description}<br>"
  body += "Provision tags: #{@task.get_tags}<br>"
  body += "Template: #{@task.vm_template.name}<br>"
  body += "Template vendor: #{@task.vm_template.vendor}<br>"
  body += "Template guid: #{@task.vm_template.guid}<br>"
  body += "Template Tags: #{@task.vm_template.tags}<br>"
  body += "Service: #{service.name}<br>" if service
  body += "User: #{requester.userid}<br>"
  body += "Group: #{requester.current_group.description}<br><br>"
  body += "Provision Full Summary:<br>"
  @task.options.each { |k,v| body += "Provision Option: {#{k.inspect}=>#{v.inspect}}<br>" }
  body += footer
  body
end

def administrator_email
  log(:info, "Administrator email logic starting")
  subject = "Provision task #{@task.id} has failed for #{requester.userid}"
  send_mail(administrator_email_address, from_email_address, subject, administrator_text)
end

begin
  @task = $evm.root['miq_provision']
  @ws_values = @task.options.fetch(:ws_values, {})
  @miq_request = @task.miq_request
  log(:info, "task: #{@task.id} request: #{@miq_request.id} message: #{@task.message}")

  requester_email
  administrator_email

rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_STOP
end

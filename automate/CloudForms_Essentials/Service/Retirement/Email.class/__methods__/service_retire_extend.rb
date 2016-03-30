=begin
  service_retire_extend.rb

  Author: Kevin Morey <kevin@redhat.com>

  Description: This method will add a retirement extension to the the oldest 
    retires_on and retirement_warn found on a service and all child vms.
  
  Example: service retires_on = '2015-11-11', vm1 retires_on = '2015-06-16'. 
           The service and all child vms will retire on '2015-06-16' (the oldest).
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

def log(level, msg, update_message=false)
  $evm.log(level, "#{msg}")
end

def dump_root()
  log(:info, "Begin $evm.root.attributes")
  root.attributes.sort.each { |k, v| log(:info, "\t Attribute: #{k} = #{v}")}
  log(:info, "End $evm.root.attributes")
  log(:info, "")
end

begin
  dump_root()

  # Number of days to extend retirement
  retire_extend_days = nil || $evm.root['dialog_retire_extend_days'] || $evm.object['service_retire_extend_days']
  retire_extend_days = retire_extend_days.to_i
  log(:info, "Number of days to extend: #{retire_extend_days}")

  service = $evm.root['service']
  service.attributes.each {|k, v| log(:info, "Service: #{service.name} updated {#{k} => #{v.inspect}}") if k.include?('retire') }
  retirement_dates = []
  retirement_warnings = []

  log(:info, "Service: #{service.name} - retires_on: #{service.retires_on} retirement_warn: #{service.retirement_warn}")
  retirement_dates << service.retires_on.to_s
  retirement_warnings << service.retirement_warn

  service.vms.each do |vm|
    log(:info, "VM: #{vm.name} - retires_on: #{vm.retires_on} retirement_warn: #{vm.retirement_warn}")
    retirement_dates << vm.retires_on.to_s
    retirement_warnings << vm.retirement_warn
  end

  oldest_date = retirement_dates.sort!.last
  log(:info, "Retirement date: #{oldest_date} found out of retirement_dates: #{retirement_dates}")
  largest_warning = retirement_warnings.sort!.last
  log(:info, "Retirement warning: #{largest_warning} found out of retirement_warnings: #{retirement_warnings}")

  unless oldest_date.blank?
    new_date = oldest_date.to_date + retire_extend_days
    log(:info, "Adding extended retirement date: #{new_date.to_s}")
    service.retires_on = new_date.to_s
    service.retirement_warn = largest_warning
    service.attributes.each {|k, v| log(:info, "Service: #{service.name} updated {#{k} => #{v.inspect}}") if k.include?('retire') }
    vm_body = ''
    service.vms.each do |vm|
      vm.retires_on = new_date.to_s
      vm.retirement_warn = largest_warning
      vm.attributes.each {|k, v| log(:info, "VM: #{vm.name} updated {#{k} => #{v.inspect}}") if k.include?('retire') }
      vm_body += "<br><br>The retirement date for VM: #{vm.name} has been set to: #{vm.retires_on} warning: #{vm.retirement_warn} days."
    end
    # Get Service Owner Name and Email
    owner_id = service.evm_owner_id
    owner = $evm.vmdb('user', owner_id) unless owner_id.nil?

    # to_email_address from owner.email then from model if nil
    to = owner.email if owner.email
    to ||= $evm.object['to_email_address']

    # Get from_email_address from model unless specified below
    from = nil || $evm.object['from_email_address']

    # Get signature from model unless specified below
    signature = nil || $evm.object['signature']

    # email subject
    subject = "Service Retirement Extended for #{service.name}"

    # Build email body
    body = "Hello, "
    body += "<br><br>The retirement date for service: #{service.name} has been set to: #{service.retires_on} warning: #{service.retirement_warn} days."
    body += vm_body
    body += "<br><br> Thank you,"
    body += "<br> #{signature}"

    # Send email
    log(:info, "Sending email to #{to} from #{from} subject: #{subject}")
    $evm.execute('send_email', to, from, subject, body)
  end

  # Set Ruby rescue behavior
rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

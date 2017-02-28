=begin
 vm_retire_extend.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method is used to add X number of days to a vms retirement 
    date when target VM has a retires_on value and is not already retired
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

def dump_vm_retirement_attributes
  @vm.attributes.each {|key,val| log(:info, "VM: #{@vm.name} {#{key}=>#{val.inspect}}") if key.starts_with?('retire')}
end

def from_email_address
  $evm.object['from_email_address']
end

def to_email_address
  owner = @vm.owner || $evm.vmdb(:user).find_by_id(@vm.evm_owner_id) || $evm.root['user']
  owner_email = owner.email || $evm.object['to_email_address']
  owner_email
end

def signature
  $evm.object['signature']
end

def subject
  "VM: #{@vm.name} retirement extended #{vm_retire_extend_days} days"
end

def body
  body = "Hello, "
  body += "<br><br>The retirement date for your virtual machine: #{@vm.name} has been extended to: #{@vm.retires_on}."
  body += "<br><br> Thank you,"
  body += "<br> #{signature}"
  body
end

begin
  @vm = $evm.root['vm']
  dump_vm_retirement_attributes

  vm_retire_extend_days = ( $evm.root['dialog_retire_extend_days'] || $evm.object['vm_retire_extend_days'] ).to_i
  unless vm_retire_extend_days.zero? || @vm.retires_on.nil?
    log(:info, "Extending retirement #{vm_retire_extend_days} days for VM: #{@vm.name}")

    # Set new retirement date here
    @vm.retires_on += vm_retire_extend_days.days
    dump_vm_retirement_attributes

    # Send email
    log(:info, "Sending email to #{to} from #{from} subject: #{subject}")
    $evm.execute('send_email', to_email_address, from_email_address, subject, body)
  end

rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_STOP
end

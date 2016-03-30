=begin
  scan_guest_for_file_via_ssa.rb

  Author: Kevin Morey <kevin@redhat.com>

  Description: This method is used to check for error.log and complete.log on the VM.
    If log files are not found then initiate SmartState Analysis (SSA) and retry
    otherwise grab the first line in the file. NOTE - Ensure that the file(s) you
    are looking for are noted in the SSA scan profile
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

def retry_method(retry_time='1.minute', msg='RETRYING', update_message=false)
  log(:info, "#{msg} - retrying in #{retry_time}}", update_message)
  $evm.root['ae_result'] = 'retry'
  $evm.root['ae_retry_interval'] = retry_time
  exit MIQ_OK
end

begin
  $evm.root.attributes.sort.each { |k, v| log(:info, "$evm.root Attribute - #{k}: #{v}")}

  case $evm.root['vmdb_object_type']
  when 'miq_provision'
    @task = $evm.root['miq_provision']
    log(:info, "Task: #{@task.id} Request: #{@task.miq_request.id} Type:#{@task.type}")
    # get vm object from miq_provision. This assumes that the vm container on the management system is present
    @vm = @task.vm
  when 'vm'
    # get vm from root
    @vm = $evm.root['vm']
    log(:info, "VM: #{@vm.name} vendor: #{@vm.vendor}")
  else
    exit MIQ_OK
  end

  error_log = 'error.log'
  complete_log = 'complete.log'

  # Initialize message
  message = nil
  filename = nil

  # Loop through scanned files
  files = @vm.files
  files.each do |f|
    if f.name.downcase.include?(error_log) || f.name.downcase.include?(complete_log)
      contents = f.contents
      unless contents.nil?
        lines = contents.split("\n")
        lines.each_with_index do |line, idx|

          message = line.chomp
          filename = f.base_name.downcase
          log(:info, "Found file:<#{f.name}> size:<#{f.size}> message:<#{message}>")
          break
        end
      end
    end
  end

  # If log files not found
  if message.nil?
    @vm.scan
    retry_method('5.minutes', "file(s) not found on VM: #{@vm.name} initiating SmartState Analysis")
  else
    if filename == 'complete.log'
      log(:info, "Post Installation successfully completed", true)
    else
      log(:info, "Post Installation failed on VM: #{@vm.name}")
    end
  end

  # Ruby rescue
rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

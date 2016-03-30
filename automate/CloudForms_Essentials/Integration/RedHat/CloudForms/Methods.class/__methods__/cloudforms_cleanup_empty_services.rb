=begin
 cloudforms_cleanup_empty_services.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method removes all services with no vms associated
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
  $evm.root.attributes.sort.each { |k, v| log(:info, "\t $evm.root Attribute - #{k}: #{v}")}

  case $evm.root['vmdb_object_type']
  when 'service_template_provision_task'
    @task = $evm.root['service_template_provision_task']
    @service = @task.destination
  when 'service'
    @service = $evm.root['service']
  end

  empty_services = $evm.vmdb(:service).all.select {|s| s.vms.count.zero? }
  empty_services.each do |svc|
    unless svc.id == @service.id
      log(:info, "removing service: #{svc.name} with vm count: #{svc.vms.count} from vmdb", true)
      svc.remove_from_vmdb
    end
  end

  # remove the current service if it exists and qualifies
  if @service && @service.vms.count.zero?
    log(:info, "removing current service: #{@service.name} with vm count: #{@service.vms.count} from vmdb", true)
    @service.remove_from_vmdb
  end

rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  @service.remove_from_vmdb if @service
  exit MIQ_ABORT
end

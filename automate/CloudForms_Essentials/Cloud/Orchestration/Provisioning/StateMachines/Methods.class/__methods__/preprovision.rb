=begin
  preprovision.rb

  Author: Nate Stephany <nate@redhat.com>

  Description: This is an extended preprovision method for deploying OpenStack
  			   Heat stacks that rely on nested templates. It will read those
  			   nested templates out of CloudForms and feed them in as a string.

  Mandatory dialog fields: dialog_nested_template_XXX where XXX is the name of
  						   your nested template yaml file (i.e. worker.yaml)
-------------------------------------------------------------------------------
   Copyright 2016 Nate Stephany <nate@redhat.com>

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

#
# TODO: test and extend this to make sure it works with other provider orchestration
#

log("info", "Starting Orchestration Pre-Provisioning")

service = $evm.root["service_template_provision_task"].destination

log("info", "manager = #{service.orchestration_manager.name}(#{service.orchestration_manager.id})")
log("info", "template = #{service.orchestration_template.name}(#{service.orchestration_template.id}))")
log("info", "stack name = #{service.stack_name}")

service.name = service.stack_name
stack_options = service.stack_options

$evm.root.attributes.sort.each { |k, v| log(:info, "\t $evm.root Attribute - #{k}: #{v}")}
nested_templates = {}
log(:info, "created empty hash for #{nested_templates.inspect}")
template_regex = /dialog_nested_template\w/

$evm.root.attributes.each { |k,v| nested_templates[k] = ($evm.vmdb(:orchestration_template).all.detect \
                                                         { |t| t.id == v.to_i }.content) if k.to_s =~ template_regex }
log(:info, "populated nested_templates hash with values: #{nested_templates.inspect}")
nested_templates.clone.each { |k,v| nested_templates[k.sub(/dialog_nested_template_/, '')] = nested_templates.delete(k) }
log(:info, "stripped prefixes from keys in nested_templates: #{nested_templates.inspect}")
nested_templates.clone.each { |k,v| nested_templates[k.sub(/$/, '.yaml')] = nested_templates.delete(k) }
log(:info, "appended .yaml to nested template name to make it all work: #{nested_templates.inspect}")

unless nested_templates.blank?
  stack_options[:files] = nested_templates
  service.stack_options = stack_options
end

=begin
  openstack_customizerequest.rb

  Author: Kevin Morey <kevin@redhat.com>

  Description: This method is used to customize the Openstack provisioning tasks
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

# process_customization - mapping instance_types, key pairs, security groups and cloud-init templates
def process_customization(mapping)
  log(:info, "Processing Openstack customizations...", true)
  case mapping
  when 0
    # No mapping
  when 1
    ws_values = @task.options.fetch(:ws_values, {})

    if @task.get_option(:instance_type).nil? && ws_values.has_key?(:instance_type)
      @provider.flavors.each do |flavor|
        if flavor.name.downcase == ws_values[:instance_type].downcase
          @task.set_option(:instance_type, [flavor.id, "#{flavor.name}':'#{flavor.description}"])
          log(:info, "Provisioning object updated {:instance_type => #{@task.get_option(:instance_type).inspect}}")
        end
      end
    end

    if @task.get_option(:guest_access_key_pair).nil? && ws_values.has_key?(:guest_access_key_pair)
      @provider.key_pairs.each do |keypair|
        if keypair.name == ws_values[:guest_access_key_pair]
          @task.set_option(:guest_access_key_pair, [keypair.id,keypair.name])
          log(:info, "Provisioning object updated {:guest_access_key_pair => #{@task.get_option(:guest_access_key_pair).inspect}}")
        end
      end
    end

    if @task.get_option(:security_groups).blank?
      security_group_search_criteria = ws_values[:security_groups] || ws_values[:security_groups_id] ||
        @task.get_option(:security_groups_id)
      security_group = @provider.security_groups.detect {|sg|
        sg.id == security_group_search_criteria.to_i || sg.name == security_group_search_criteria
      }
      if security_group
        @task.set_option(:security_groups, security_group.id)
        log(:info, "Provisioning option updated {:security_groups=>#{@task.get_option(:security_groups).inspect}}")
      end
    end

    if @task.get_option(:customization_template_id).nil?
      customization_template_search_by_function       = "#{@task.type}_#{@task.get_tags[:function]}" rescue nil
      customization_template_search_by_role           = "#{@task.type}_#{@task.get_tags[:role]}" rescue nil
      customization_template_search_by_template_name  = @template.name
      customization_template_search_by_ws_values      = ws_values[:customization_template] rescue nil
      log(:info, "eligible_customization_templates: #{@task.eligible_customization_templates.inspect}")
      customization_template = nil

      unless customization_template_search_by_function.nil?
        if customization_template.blank?
          log(:info, "Searching for customization templates (Cloud-Init) enabled that are named: #{customization_template_search_by_function}")
          customization_template = @task.eligible_customization_templates.detect { |ct| ct.name.casecmp(customization_template_search_by_function)==0 }
        end
      end
      unless customization_template_search_by_role.nil?
        if customization_template.blank?
          log(:info, "Searching for customization templates (Cloud-Init) enabled that are named: #{customization_template_search_by_role}")
          customization_template = @task.eligible_customization_templates.detect { |ct| ct.name.casecmp(customization_template_search_by_role)==0 }
        end
      end
      unless customization_template_search_by_template_name.nil?
        # Search for customization templates enabled for Cloud-Init that match the template/image name
        if customization_template.blank?
          log(:info, "Searching for customization templates (Cloud-Init) enabled that are named: #{customization_template_search_by_template_name}")
          customization_template = @task.eligible_customization_templates.detect { |ct| ct.name.casecmp(customization_template_search_by_template_name)==0 }
        end
      end
      unless customization_template_search_by_ws_values.nil?
        # Search for customization templates enabled for Cloud-Init that match ws_values[:customization_template]
        if customization_template.blank?
          log(:info, "Searching for customization templates (Cloud-Init) enabled that are named: #{customization_template_search_by_ws_values}")
          customization_template = @task.eligible_customization_templates.detect { |ct| ct.name.casecmp(customization_template_search_by_ws_values)==0 }
        end
      end
      if customization_template.blank?
        log(:warn, "Failed to find matching Customization Template", true)
      else
        log(:info, "Found Customization Template ID: #{customization_template.id} Name: #{customization_template.name} Description: #{customization_template.description}")
        @task.set_customization_template(customization_template) rescue nil
        log(:info, "Provisioning object updated {:customization_template_id => #{@task.get_option(:customization_template_id).inspect}}")
        log(:info, "Provisioning object updated {:customization_template_script => #{@task.get_option(:customization_template_script).inspect}}")
      end
    else
      log(:info, "Customization Template selected from dialog ID: #{@task.get_option(:customization_template_id).inspect}} Script: #{@task.get_option(:customization_template_script).inspect}")
    end
  end # case mapping
  log(:info, "Processing Openstack customizations...Complete", true)
end

begin
  @task = $evm.root["miq_provision"]
  log(:info, "Provision:<#{@task.id}> Request:<#{@task.miq_provision_request.id}> Type:<#{@task.type}>")

  @template = @task.vm_template
  @provider = @template.ext_management_system
  @product  = @template.operating_system['product_name'].downcase rescue nil
  log(:info, "Template: #{@template.name} Provider: #{@provider.name} Vendor: #{@template.vendor} product: #{@product}")

  mapping = 1
  process_customization(mapping)

  # Log all of the provisioning options to the automation.log
  @task.options.each { |k,v| log(:info, "Provisioning Option Key: #{k.inspect} Value: #{v.inspect}") }

rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end

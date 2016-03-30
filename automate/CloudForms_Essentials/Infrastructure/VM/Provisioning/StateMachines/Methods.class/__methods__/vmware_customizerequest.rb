=begin
 vmware_customizerequest.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method is used to set VMware customization specifications and customization templates (kickstart)
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

def set_customspec(spec)
  return if spec.nil?
  @task.set_customization_spec(spec, true)
  unless @task.get_option(:sysprep_custom_spec).blank?
    log(:info, "Provisioning option updated {:sysprep_custom_spec=>" \
                           "#{@task.options[:sysprep_custom_spec]}}")
    log(:info, "Provisioning option updated {:sysprep_spec_override=>" \
                           "#{@task.get_option(:sysprep_spec_override)}}")
  end
end

def find_eligible_image(eligible_images_method=:eligible_pxe_images, eligible_image=nil)
  # search for an [pxe, iso, windows] image by id, name, one that matches the template name
  # and finally just pick the first one available (this may not always be the best choice)
  log(:info, "Processing find_eligible_image...", true)

  image_search_criteria = @ws_values[:image_id] || @ws_values[:image_name] || @template.name
  log(:info, "image_search_criteria: #{image_search_criteria}")

  @task.send(eligible_images_method).each {|x| log(:info, "#{eligible_images_method}: #{x}")}
  eligible_image = @task.send(eligible_images_method).detect { |ei| ei.id == image_search_criteria.to_i } ||
    @task.send(eligible_images_method).detect { |ei| ei.name.casecmp(image_search_criteria)==0 } ||
    @task.send(eligible_images_method).first
  raise "no #{eligible_images_method} found" if eligible_image.nil?
  log(:info, "Found #{eligible_images_method}: #{eligible_image}")
  log(:info, "Processing find_eligible_image...Complete", true)
  return eligible_image
end

def find_and_set_eligible_customization_template(eligible_template=nil)
  # search for a [kickstart, cloud-init, sysprep] customization_template by id, name, one
  # that matches the template name and finally just pick the first one available
  # (this may not always be the best choice)
  log(:info, "Processing find_and_set_eligible_customization_template...", true)

  if @task.get_option(:customization_template_id).nil?
    customization_template_search_criteria = @ws_values[:customization_template_id] ||
      @ws_values[:image_name] || @template.name
    log(:info, "customization_template_search_criteria: " \
                           "#{customization_template_search_criteria}")
    @task.eligible_customization_templates.each \
      {|ct| log(:info, "eligible_customization_template: #{ct}")}

    eligible_template = @task.eligible_customization_templates.detect { |ct|
    ct.id == customization_template_search_criteria.to_i } ||
    @task.eligible_customization_templates.detect { |ct|
    ct.name.casecmp(customization_template_search_criteria)==0 } ||
      @task.eligible_customization_templates.first

    if eligible_template
      log(:info, "Found #{eligible_templates_method}: #{eligible_template}")
      @task.set_customization_template(eligible_template)
      log(:info, "Provisioning option updated {:customization_template_id=>" \
                             "#{@task.options[:customization_template_id]}}")
      log(:info, "Provisioning option updated {:customization_template_script" \
                             "=> #{@task.get_option(:customization_template_script)}}")
    else
      log(:warn, "no eligible_customization_templates found", true)
    end
  else
    log(:info, "Customization Template selected from dialog: " \
                           "#{@task.options[:customization_template_id]}")
  end
  log(:info, "Processing find_and_set_eligible_customization_template...Complete", true)
end

def vmware_native_clone
  # find eligible customization_specifications
  log(:info, "Processing vmware_native_clone...", true)

  if @task.get_option(:sysprep_custom_spec).nil?
    customization_spec_search_criteria = @ws_values[:custom_spec] ||
      @task.get_option(:custom_spec) || @template.name

    # log all eligible customization specs (I believe it is looking at the type parameter)
    @task.eligible_customization_specs.each {|cs| log(:info, "eligible custom_spec " \
                                                                         "name: #{cs.name} spec: #{cs.inspect}") }

    # search eligible customization spec first by name, id, then description and finally default to first eligible
    customization_spec   = @task.eligible_customization_specs.detect \
      { |cs| cs.name.casecmp(customization_spec_search_criteria)==0 } ||
      @task.eligible_customization_specs.detect { |cs| cs.id == customization_spec_search_criteria.to_i } ||
      @task.eligible_customization_specs.detect { |cs| cs.description == customization_spec_search_criteria } ||
      @task.eligible_customization_specs.first
    if customization_spec
      log(:info, "Found customization_spec name: #{customization_spec.name} spec: " \
                             "#{customization_spec}")
      set_customspec(customization_spec)
    else
      log(:info, "No eligible customization_specs found", true)
    end
  else
    log(:info, "Customization specification already chosen via dialog: "\
                           "#{@task.options[:sysprep_custom_spec]}")

    # by default always override custom spec even unless already set to true
    @task.set_option(:sysprep_spec_override, [true, 1])
    log(:info, "Provisioning option updated {:sysprep_spec_override=>" \
                           "#{@task.options[:sysprep_spec_override]}}")
  end
  # For linux vms using a customization spec we need to set the linux_hostname
  if @task.get_option(:linux_host_name).nil?
    @task.set_option(:linux_host_name, @task.get_option(:vm_target_hostname))
    log(:info, "Provisioning option updated {:linux_host_name=>" \
                           "#{@task.get_option(:linux_host_name)}}")
  end
  log(:info, "Processing vmware_native_clone...Complete", true)
end

def vmware_pxe
  # find eligible [pxe,windows] images and [kickstart,sysprep] customization_templates
  log(:info, "Processing vmware_pxe...", true)
  if @task.get_option(:pxe_image_id).nil?
    if @product.include?("windows")
      eligible_images_method = :eligible_windows_images
      eligible_image = find_eligible_image(eligible_images_method)
      @task.set_windows_image(eligible_image)
    else
      eligible_images_method = :eligible_pxe_images
      eligible_image = find_eligible_image(eligible_images_method)
      @task.set_pxe_image(eligible_image)
    end
    log(:info, "Provisioning option updated {:pxe_image_id=>" \
                           "#{@task.options[:pxe_image_id]}}")
  else
    log(:info, "Image selected from dialog: #{@task.options[:pxe_image_id]}")
  end
  find_and_set_eligible_customization_template()
  log(:info, "Processing vmware_pxe...Complete", true)
end

begin
  # Get provisioning object
  @task = $evm.root["miq_provision"]
  log(:info, "Provision:<#{@task.id}> Request:<#{@task.miq_provision_request.id}> " \
                         "provision_type:<#{@task.get_option(:provision_type)}>")

  @ws_values = @task.options.fetch(:ws_values, {})
  @template = @task.vm_template
  @provider = @template.ext_management_system
  @product  = @template.operating_system['product_name'].downcase rescue nil
  log(:info, "Template: #{@template.name} Provider: #{@provider.name} " \
                         "Vendor: #{@template.vendor} Product: #{@product}")

  # Build case statement to determine which type of processing is required
  case @task.get_option(:provision_type)
  when 'vmware'
    # VMware Customization Specification
    vmware_native_clone
  when 'pxe'
    # VMware PXE Customization Template
    vmware_pxe
  else
    log(:info, "provision_type: #{@task.get_option(:provision_type)} " \
                           "does not match, skipping processing")
  end

  # Log all of the provisioning options to the automation.log
  @task.options.each { |k,v| log(:info, "Provisioning option: {#{k}=>#{v.inspect}}") }

  # Set Ruby rescue behavior
rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_STOP
end

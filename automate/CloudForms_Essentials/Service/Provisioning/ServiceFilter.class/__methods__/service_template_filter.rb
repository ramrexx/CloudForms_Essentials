=begin
 service_template_filter.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method is used to filter service_templates (catalogitems) 
  that are in a bundle tagged with 'service_template_filter'. This method 
  must be called from /Service/Provisioning/Profile/.missing

 For example:
  1. create a openstack catalogitem tagged with {:environment=>'test'}
  2. create a redhat catalogitem tagged with {:environment=>'dev'}
  3. create a amazon catalogitem tagged with {:environment=>'prod'}
  4. create a bundle with the above catalog items 
  5. tag the bundle with {:service_template_filter=>'environment'} 
  6. order the bundle simple dialog which prompts the end user for an 
     tag_0_environment (dev, test, or prod), select 'test' 
  7. during the service filtering method:
    a) the filtering method will continue as normal if the bundle is not 
       tagged with {:service_template_filter=>'environment'}
    b) Only the catalogitem(s) tagged with {:environment=>'test'} in this 
       case openstack will be executed

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
$evm.root['include_service'] = true

service_template = $evm.root['service_template']
raise "service_template missing" unless service_template

service_template_provision_task = $evm.root['service_template_provision_task']
raise "service_template_provision_task missing" unless service_template_provision_task

miq_request = service_template_provision_task.miq_request
raise "service provision request missing" unless miq_request

service = $evm.root['service']

if service.nil?
  # include service if this is the top level service with no parent
  $evm.log('info', "root service will be installed")
elsif service_template.service_type == 'composite'
  # include service if bundle is detected
  $evm.log('info', "bundle service will be installed")
else
  # check the catalog bundle for a service_template_filter tag
  service_template_filter = miq_request.source.tags(:service_template_filter).first rescue nil
  $evm.log('info', "service_template_filter: #{service_template_filter}")

  dialog_options = miq_request.options[:dialog]
  $evm.log('info', "dialog_options: #{dialog_options}")

  # use this case statement to plug in your own service_filters
  case service_template_filter
  when 'environment'
    # Exclude catalogitem(s) that are not tagged with environment
    dialog_env = dialog_options["dialog_environment"] || dialog_options["dialog_tag_0_environment"]
    item_env = service_template.tags(:environment).first
    $evm.log('info', "dialog_env: #{dialog_env} item_env: #{item_env}")
    if dialog_env && item_env
      unless dialog_env == item_env
        $evm.root['include_service'] = false
      end
    end
  when 'location'
    # Filter out catalogitems(s) that are not tagged with location
    dialog_loc = dialog_options["dialog_location"] || dialog_options["dialog_tag_0_location"]
    item_loc = service_template.tags(:location).first
    $evm.log('info', "dialog_loc: #{dialog_loc} item_loc: #{item_loc}")
    if dialog_loc && item_loc
      unless dialog_loc == item_loc
        $evm.root['include_service'] = false
      end
    end
   when 'foo'
    # add your own filter here

  end

end

$evm.log('info', "Include Service: #{service_template.name} Value: #{$evm.root['include_service']}")

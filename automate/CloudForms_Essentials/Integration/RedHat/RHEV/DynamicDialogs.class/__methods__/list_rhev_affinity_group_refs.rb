=begin
 list_rhev_affinity_group_refs.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: List all affinity groups associated with a oVIRT cluster
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

def get_provider(provider_id=nil)
  $evm.root.attributes.detect { |k,v| provider_id = v if k.end_with?('provider_id') } rescue nil
  provider = $evm.vmdb(:ManageIQ_Providers_Redhat_InfraManager).find_by_id(provider_id)
  log(:info, "Found provider: #{provider.name} via provider_id: #{provider.id}") if provider

  if provider.nil?
    provider = $evm.vmdb(:ManageIQ_Providers_Redhat_InfraManager).first
    log(:info, "Found provider: #{provider.name} via default method")
  end
  provider ? (return provider) : (return nil)
end

def query_catalogitem(option_key, option_value=nil)
  # use this method to query a catalogitem
  # note that this only works for items not bundles since we do not know which item within a bundle(s) to query from
  service_template = $evm.root['service_template']
  unless service_template.nil?
    begin
      if service_template.service_type == 'atomic'
        log(:info, "Catalog item: #{service_template.name}")
        service_template.service_resources.each do |catalog_item|
          catalog_item_resource = catalog_item.resource
          if catalog_item_resource.respond_to?('get_option')
            option_value = catalog_item_resource.get_option(option_key)
          else
            option_value = catalog_item_resource[option_key] rescue nil
          end
          log(:info, "Found {#{option_key} => #{option_value}}") if option_value
        end
      else
        log(:info, "Catalog bundle: #{service_template.name} found, skipping query")
      end
    rescue
      return nil
    end
  end
  option_value ? (return option_value) : (return nil)
end

def get_template(template_guid=nil)
  template = $evm.vmdb(:ManageIQ_Providers_Redhat_InfraManager_Template).find_by_id(query_catalogitem(:src_vm_id))
  unless template
    $evm.root.attributes.detect { |k,v| template_guid = v if k.end_with?('_guid') } rescue nil
    template = $evm.vmdb(:ManageIQ_Providers_Redhat_InfraManager_Template).find_by_guid(template_guid)
  end
  return template
end

def call_rhev(action, ref=nil, body_type=:json, body=nil)
  require 'rest_client'
  require 'json'
  servername = @provider.hostname
  username   = @provider.authentication_userid
  password   = @provider.authentication_password

  unless ref.nil?
    url = ref if ref.include?('http')
  end
  url ||= "https://#{servername}"+"#{ref}"

  params = {
    :method=>action, :url=>url,:user=>username, :password=>password,
    :verify_ssl=>false, :headers=>{ :content_type=>body_type, :accept=>:json }
  }
  body_type == :json ? (params[:payload] = JSON.generate(body) if body) : (params[:payload] = body if body)
  log(:info, "Calling url: #{url} action: #{action} payload: #{params[:payload]}")

  begin
    response = RestClient::Request.new(params).execute
    log(:info, "response headers: #{response.headers.inspect}")
    log(:info, "response code: #{response.code}")
    log(:info, "response: #{response.inspect}")
    return JSON.parse(response) rescue (return response)
  rescue rheverr
    log(:warn, "rheverr: #{rheverr}")
    return {}
  end
end

$evm.root.attributes.sort.each { |k, v| log(:info, "$evm.root Attribute - #{k}: #{v}")}

@template = get_template
@provider = get_provider(query_catalogitem(:src_ems_id)) || @template.ext_management_system rescue nil

dialog_hash = {}

cluster = @template.ems_cluster if @template
cluster_afinity_groups = call_rhev(:get, "#{cluster.ems_ref}/affinitygroups")
cluster_afinity_groups['affinity_group'].each { |ag| dialog_hash[ag['href']] = ag["name"] }

if dialog_hash.blank?
  dialog_hash[''] = "< no affinity groups found >"
  $evm.object['required'] = false
else
  $evm.object['default_value'] = dialog_hash.first[0]
end

$evm.object["values"]     = dialog_hash
log(:info, "$evm.object['values']: #{$evm.object['values'].inspect}")

=begin
 list_rhev_external_provider_glance_ids.rb

 Author: David Costakos <dcostako@redhat.com>, Kevin Morey <kevin@redhat.com>

 Description: This method is used to dynamically search for missing 
    customization_templates, pxe_images, iso_images and windows_images 
    for RHEV provisioning
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

  response = RestClient::Request.new(params).execute
  log(:info, "response headers: #{response.headers.inspect}")
  log(:info, "response code: #{response.code}")
  log(:info, "response: #{response.inspect}")
  return JSON.parse(response) rescue (return response)
end


$evm.root.attributes.sort.each { |k, v| log(:info, "\t$evm.root Attribute - #{k}: #{v}")}

case $evm.root['vmdb_object_type']
when 'provider'
  provider_id = $evm.root['ext_management_system'].id
when 'vm'
  provider_id = $evm.root['vm'].ext_management_system.id
else
  provider_id = $evm.root['dialog_provider_id']
end
raise if provider_id.nil?
@provider = $evm.vmdb('ext_management_system').find_by_id(provider_id)
raise "Unable to get provider" if @provider.nil?
log(:info, "Got provider #{@provider.name}")

dialog_hash = {}

storagedomains_hash = call_rhev(:get, "/api/storagedomains")
log(:info, "storagedomains_hash: #{storagedomains_hash}")

image_domain = storagedomains_hash["storage_domain"].detect {|sd| sd['type'] == "data" }
if image_domain.blank?
  error_message = "No image domains found"
  (dialog_hash={})[''] = error_message
  $evm.object["values"] = dialog_hash
  raise error_message
end

log(:info, "image_domain: #{image_domain}")
images = call_rhevm(:get, "#{image_domain['href']}/images")["image"]
log(:info, "images: #{images}")

images.each {|image| dialog_hash["#{image['id']}"] = "#{image["name"].first}" }
$evm.object["values"] = dialog_hash.first[0]
log(:info, "Dialog Values: <#{$evm.object['values'].inspect}>")

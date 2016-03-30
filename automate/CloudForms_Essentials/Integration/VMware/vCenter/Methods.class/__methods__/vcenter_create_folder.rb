=begin
 vcenter_create_folder.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method creates a folder path in VMware vCenter and sets the provision option 
    :placement_folder_name to the folder object
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
  @task.message = msg if @task && (update_message || level == 'error')
end

def vmware_login(provider)
  result = @client.call(:login) do
    message( :_this => "SessionManager", :userName => provider.authentication_userid, :password => provider.authentication_password )
  end
  @client.globals.headers({ "Cookie" => result.http.headers["Set-Cookie"] })
end

def vmware_logout()
  begin
    @client.call(:logout) do
      message(:_this => "SessionManager")
    end
  rescue => logouterr
    log(:error, "Error logging out #{logouterr.class} #{logouterr}")
  end
end

def vmware_root_folder()
  body_hash = {
    :_this  =>     "ServiceInstance",
    :attributes! => {  :_this =>  { 'type' => 'ServiceInstance' } }
  }
  result = @client.call(:retrieve_service_content, message: body_hash).to_hash
  log(:info, "vmware_root_folder results: #{result.inspect}")
  rootFolder = result[:retrieve_service_content_response][:returnval][:root_folder]
  return rootFolder
end

def vmware_datacenters(folder)
  body_hash = {
    :_this  =>     "propertyCollector",
    :specSet   =>      {
      :propSet => {
        :type => "Datacenter",
        :pathSet => "name",
      },
      :objectSet => {
        :obj => folder,
        :skip => false,
        :selectSet => {
          :name => 'visitFolders',
          :type => 'Folder',
          :path => 'childEntity',
          :skip => false,
        },
        :attributes! => {
          :obj =>  { 'type' => 'Folder' },
          :selectSet =>  { 'xsi:type' => 'TraversalSpec' }
        },
      },
    },
    :options => {},
    :attributes! => {  :_this =>  { 'type' => 'PropertyCollector' } }
  }
  result = @client.call(:retrieve_properties_ex, message: body_hash).to_hash
  log(:info, "vmware_datacenters results: #{result.inspect}")
  result_hash = result[:retrieve_properties_ex_response][:returnval][:objects]
  return result_hash
end

def vmware_parent_folders(folder)
  body_hash = {
    :_this  =>     "propertyCollector",
    :specSet   =>      {
      :propSet => {
        :type => "Folder",
        :pathSet => "parent",
      },
      :objectSet => {
        :obj => folder,
        :skip => true,
        :selectSet => {
          :name => 'visitFolders',
          :type => 'Folder',
          :path => 'childEntity',
          :skip => false,
          :selectSet => {
            :name => 'dcToVmf',
            :type => 'Datacenter',
            :path => 'vmFolder',
            :skip => false,
            :selectSet => {
              :name => 'visitFolders',
            },
          },
          :attributes! => {
            :selectSet =>  { 'xsi:type' => 'TraversalSpec' }
          },
        },
        :attributes! => {
          :obj =>  { 'type' => 'Folder' },
          :selectSet =>  { 'xsi:type' => 'TraversalSpec' },
        },
      },
    },
    :options => {},
    :attributes! => {  :_this =>  { 'type' => 'PropertyCollector' } }
  }
  result = @client.call(:retrieve_properties_ex, message: body_hash).to_hash
  log(:info, "vmware_parent_folders results: #{result.inspect}")
  result_hash = result[:retrieve_properties_ex_response][:returnval][:objects]
  return result_hash
end

def vmware_find_folder(folder, folder_check)
  body_hash = {
    :_this  =>     "propertyCollector",
    :specSet   =>      {
      :propSet => {
        :type => "Folder",
        :pathSet => "name",
      },
      :objectSet => {
        :obj => folder,
        :skip => false,
        :selectSet => {
          :name => 'visitFolders',
          :type => 'Folder',
          :path => 'childEntity',
          :skip => false,
          :selectSet => {
            :name => 'dcToVmf',
            :type => 'Datacenter',
            :path => 'vmFolder',
            :skip => false,
            :selectSet => {
              :name => 'visitFolders',
            },
          },
          :attributes! => {
            :selectSet =>  { 'xsi:type' => 'TraversalSpec' }
          },
        },
        :attributes! => {
          :obj =>  { 'type' => 'Folder' },
          :selectSet =>  { 'xsi:type' => 'TraversalSpec' },
        },
      },
    },
    :options => {},
    :attributes! => {  :_this =>  { 'type' => 'PropertyCollector' } }
  }
  result = @client.call(:retrieve_properties_ex, message: body_hash).to_hash
  # log(:info, "vmware_find_folder results: #{result.inspect}")
  result_hash = result[:retrieve_properties_ex_response][:returnval][:objects] rescue nil
  log(:info, "Result Hash: #{result_hash.inspect}")

  folder_ref = nil

  if result_hash.class == Hash
    if result_hash[:prop_set][:val] == folder_check
      folder_ref = result_hash[:obj]
    end
  else
    result_hash.each { |f|
      if f[:prop_set][:val] == folder_check
        folder_ref = f[:obj]
      end
    }
  end
  return folder_ref
end

def vmware_create_folder(rootFolder, folder)
  body_hash = {
    :_this  =>     rootFolder,
    :name   =>     folder,
    :attributes! => {  :_this =>  { 'type' => 'Folder' } },
  }
  result = @client.call(:create_folder, message: body_hash).to_hash
  result_hash = result[:create_folder_response]
  log(:info, "vmware_create_folder result_hash: #{result_hash.inspect}")
  # @folder_val["mor"] = result_hash[:returnval]
  return result_hash[:returnval]
end

def check_exist(parent, folder)
  log(:info, "Checking if folder: #{folder} exist inside of #{parent}")
  folder_ref = vmware_find_folder(parent , folder)
  log(:info, "folder_ref: #{folder_ref.inspect}")
  return folder_ref
end

def get_vcenter_folder_path(vcenter_folder_path=nil)
  if @task
    ws_values = @task.options.fetch(:ws_values, {}) rescue {}
    vcenter_folder_path   = @task.get_option(:vcenter_folder_path)
    vcenter_folder_path ||= ws_values[:vcenter_folder_path]
    vcenter_folder_path ||= $evm.root['dialog_vcenter_folder_path']
    vcenter_folder_path ||= $evm.object['vcenter_folder_path']

    # if vcenter_folder_path.nil?
    # group = @task.miq_request.requester.current_group rescue nil
    # unless group.nil?
    #   vcenter_folder_path = "/CloudForms/#{@group.description}" rescue nil
    # end

    # if vcenter_folder_path.nil?
    #   # uncomment the following to use a provisioning tag to dynamically create the folder
    #   prov_tags = @task.get_tags
    #   log(:info, "Provision Tags: #{prov_tags.inspect} ")
    #   tag = prov_tags[:project]
    #   if tag.nil?
    #     vcenter_folder_path = "/CloudForms/#{tag}"
    #   end
    # end
    # end
  else
    vcenter_folder_path = 'CloudForms/Dev123'
  end
  return vcenter_folder_path
end

def get_client(servername)
  require 'savon'
  Savon.client(:pretty_print_xml => true,
               :wsdl => "https://#{servername}/sdk/vim.wsdl",
               :endpoint => "https://#{servername}/sdk/vimService",
               :ssl_verify_mode => :none,
               :ssl_version => :TLSv1,
               :raise_errors => false,
               :env_namespace => :soapenv,
               :log_level => :info,
               :strip_namespaces => true,
               :convert_request_keys_to => :none,
               :log => false
               )
end

begin
  case $evm.root['vmdb_object_type']
  when 'miq_provision'
    @task = $evm.root['miq_provision']
    log(:info, "Task: #{@task.id} Request: #{@task.miq_provision_request.id} Type: #{@task.type}")
    unless @task.get_option(:placement_folder_name).nil?
      log(:info, "Provisioning object {:placement_folder_name=>#{@task.options[:placement_folder_name]}} already set")
      exit MIQ_OK
    end
    vm = prov.vm_template
  when 'vm'
    vm = $evm.root['vm']
  end

  unless vm.vendor.downcase == 'vmware'
    exit MIQ_OK
  end

  datacenter_name = vm.v_owning_datacenter

  provider   = vm.ext_management_system

  @client = get_client(provider.hostname)

  vcenter_folder_path = get_vcenter_folder_path
  log(:info, "vcenter_folder_path: #{vcenter_folder_path.inspect}")

  if vcenter_folder_path.blank?
    exit MIQ_OK
  end

  # login and set cookie
  vmware_login(provider)

  root_folder = vmware_root_folder()
  log(:info, "root_folder: #{root_folder.inspect}")

  datacenters = vmware_datacenters(root_folder)
  log(:info, "Detected datacenters: #{datacenters.inspect}")
  # Datacenters: [{:obj=>"datacenter-2", :prop_set=>{:name=>"name", :val=>"RDU-SALAB"}}, {:obj=>"datacenter-1661", :prop_set=>{:name=>"name", :val=>"TestDC"}}]
  datacenter = datacenters.detect {|dc| dc[:prop_set][:val] == datacenter_name }

  log(:info, "Datacenter: #{datacenter.inspect}")

  parent_folders = vmware_parent_folders(root_folder)
  log(:info, "Parent Folders = #{parent_folders.inspect}")

  root_parent = nil
  matching_parent_folder = parent_folders.detect { |pf| pf[:prop_set][:val] == datacenter[:obj] }
  root_parent = matching_parent_folder[:obj]

  created_folders = []

  vcenter_folder_path.split('/').reject(&:empty?).each_with_index do |folder, idx|
    if idx.zero?
      parent_folder = root_parent
    else
      parent_folder = created_folders.last
    end

    folder_ref = check_exist(parent_folder, folder) unless parent_folder.nil?

    if folder_ref.nil?
      log(:info, "Creating #{folder} inside of #{parent_folder}")
      created_folders << vmware_create_folder(parent_folder, folder)
      log(:info, "created_folders: #{created_folders.inspect}")
    else
      log(:info, "Folder #{folder} already exists")
    end
  end

  fq_path = datacenter_name + '/' + vcenter_folder_path

  if @task
    @task.set_option(:vcenter_folder_path, fq_path)
    log(:info, "Provisioning object :vcenter_folder_path updated with #{@task.options[:vcenter_folder_path]}")
  else
    $evm.root['dialog_vcenter_folder_path'] = fq_path.to_s
    $evm.root['last_vcenter_folder_ref'] = created_folders.last.to_s
    vm.custom_set(:vcenter_folder_path, fq_path.to_s)
    vm.custom_set(:last_vcenter_folder_ref, created_folders.last.to_s)
  end

rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end
